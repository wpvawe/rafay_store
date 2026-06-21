const express = require('express');
const admin = require('firebase-admin');
const https = require('https');

const MAX_MULTICAST_TOKENS = 500;
const APPROVED_STATUS = 'approved';
const VIEWER_ROLE = 'viewer';
const NOTIFICATION_ROLES = new Set(['admin', 'editor']);
const PAGE_SIZE = 100;

let adminInitialized = false;

// ── Module-level auth cache (survives across warm Vercel invocations) ────────────
// Every AI request was doing a Firestore read to check user role, burning quota
// fast. Cache the result for 4 minutes — safe because admin status rarely changes.
const _adminCache = new Map(); // uid → { isAdmin: bool, expiresAt: number }
const _authCache  = new Map(); // uid → { role: string, expiresAt: number }
const CACHE_TTL_MS = 4 * 60 * 1000; // 4 minutes

// Purge expired cache entries every 10 minutes to prevent unbounded growth.
// Without this, a long-running or warm-start server accumulates one entry
// per unique uid forever, slowly exhausting heap memory.
setInterval(() => {
  const now = Date.now();
  for (const [uid, entry] of _adminCache) {
    if (now > entry.expiresAt) _adminCache.delete(uid);
  }
  for (const [uid, entry] of _authCache) {
    if (now > entry.expiresAt) _authCache.delete(uid);
  }
}, 10 * 60 * 1000);

// ── Emergency fallback: comma-separated admin UIDs in ADMIN_UIDS env var ───────
// Set this in Vercel env vars so the server works even when Firestore quota
// is exhausted. Get UID from Firebase Console → Authentication → Users.
const ADMIN_UIDS_FALLBACK = new Set(
  (process.env.ADMIN_UIDS || '').split(',').map(s => s.trim()).filter(Boolean)
);
if (ADMIN_UIDS_FALLBACK.size > 0) {
  console.log('[Auth] ADMIN_UIDS fallback loaded:', ADMIN_UIDS_FALLBACK.size, 'UID(s)');
}

function _getCached(cache, uid) {
  const entry = cache.get(uid);
  if (!entry) return null;
  // Return entry with freshness flag — don't delete stale entries,
  // they are kept as a fallback for when Firestore quota is exceeded.
  return { ...entry, fresh: entry.expiresAt > Date.now() };
}

function ensureAdmin() {
  if (adminInitialized || admin.apps.length) { adminInitialized = true; return; }
  const rawServiceAccount = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!rawServiceAccount) throw new Error('Missing FIREBASE_SERVICE_ACCOUNT_JSON');
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(rawServiceAccount)) });
  adminInitialized = true;
}

const app = express();
app.use(express.json({ limit: '5mb' }));

function getBearerToken(req) {
  const header = req.headers.authorization || '';
  const match = header.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : '';
}

function cleanString(value, maxLength = 160) {
  if (typeof value !== 'string') return '';
  return value.trim().slice(0, maxLength);
}

function positiveInt(value, fallback = 1) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 1) return fallback;
  return parsed;
}

function chunkArray(items, size) {
  const chunks = [];
  for (let i = 0; i < items.length; i += size) chunks.push(items.slice(i, i + size));
  return chunks;
}

// ── Markdown → WhatsApp formatting converter ──────────────────────────────────
function markdownToWhatsApp(text) {
  if (!text) return text;
  return text
    .replace(/^#{1,6}\s+(.+)$/gm, '*$1*')
    .replace(/\*\*(.+?)\*\*/g, '*$1*')
    .replace(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/g, '_$1_')
    .replace(/_{2}(.+?)_{2}/g, '*$1*')
    .replace(/~~(.+?)~~/g, '~$1~')
    .replace(/`{3}[\s\S]*?`{3}/g, (m) => '```' + m.replace(/`{3}/g, '').trim() + '```')
    .replace(/`(.+?)`/g, '```$1```')
    .replace(/^\s*[-*+]\s+/gm, '• ')
    .replace(/^\s*\d+\.\s+/gm, (m) => m)
    .trim();
}

// ── Extract single action OR array of actions from AI reply ──────────────────
// Returns: { single: {action:...} | null, bulk: [{action:...}] | null }
function extractActions(text) {
  let depth = 0, start = -1;
  const candidates = [];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '{') { if (depth === 0) start = i; depth++; }
    else if (text[i] === '}') {
      depth--;
      if (depth === 0 && start !== -1) { candidates.push(text.slice(start, i + 1)); start = -1; }
    }
  }
  // Also check for top-level arrays
  let arrDepth = 0, arrStart = -1;
  const arrayCandidates = [];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '[') { if (arrDepth === 0) arrStart = i; arrDepth++; }
    else if (text[i] === ']') {
      arrDepth--;
      if (arrDepth === 0 && arrStart !== -1) { arrayCandidates.push(text.slice(arrStart, i + 1)); arrStart = -1; }
    }
  }

  // Check for {"actions":[...]} wrapper (bulk format)
  for (let i = candidates.length - 1; i >= 0; i--) {
    try {
      const obj = JSON.parse(candidates[i]);
      if (obj && Array.isArray(obj.actions) && obj.actions.length > 0) {
        return { single: null, bulk: obj.actions };
      }
    } catch {}
  }

  // Check for raw [...] array of actions
  for (let i = arrayCandidates.length - 1; i >= 0; i--) {
    try {
      const arr = JSON.parse(arrayCandidates[i]);
      if (Array.isArray(arr) && arr.length > 0 && arr[0] && typeof arr[0].action === 'string') {
        return { single: null, bulk: arr };
      }
    } catch {}
  }

  // Single action
  for (let i = candidates.length - 1; i >= 0; i--) {
    try {
      const obj = JSON.parse(candidates[i]);
      if (obj && typeof obj.action === 'string') return { single: obj, bulk: null };
    } catch {}
  }
  return { single: null, bulk: null };
}

// ── Detect pagination request and extract current offset ──────────────────────
function detectPagination(messages) {
  const latestMsg = (messages[messages.length - 1]?.content || '').toLowerCase();
  const isNextRequest = /\b(next|more|agle|baaki|aur do|aur batao|page\s*\d+|next\s*\d+|agli\s*list|agla\s*page)\b/i.test(latestMsg);
  if (!isNextRequest) return { isNext: false, offset: 0 };
  let lastOffset = 0;
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'assistant') {
      const offsetMatch = messages[i].content.match(/\[OFFSET:(\d+)\]/);
      if (offsetMatch) { lastOffset = parseInt(offsetMatch[1]) + PAGE_SIZE; break; }
      const rangeMatch = messages[i].content.match(/(\d+)-(\d+)\s*(dikh|shown|show)/i);
      if (rangeMatch) { lastOffset = parseInt(rangeMatch[2]); break; }
    }
  }
  return { isNext: true, offset: lastOffset };
}

// ── Paginated list builder ────────────────────────────────────────────────────
function buildPagedList(arr, offset, fieldKey = 'name', formatter = null) {
  const items = arr.filter(d => (d[fieldKey] || '').trim().length > 0);
  const total = items.length;
  if (total === 0) return { text: '(koi item nahi)', hasMore: false, offset, nextOffset: offset };
  const page = items.slice(offset, offset + PAGE_SIZE);
  const remaining = total - offset - page.length;
  const shown = page.map((d, i) => `${offset + i + 1}. ${formatter ? formatter(d) : d[fieldKey]}`).join('\n');
  let result = `[OFFSET:${offset}]\n`;
  if (offset > 0) result += `(Pehle ${offset} items dikh chuke)\n`;
  result += shown;
  if (remaining > 0) {
    result += `\n\n[${remaining} aur items hain — "next" ya "agle 100 do" likho]`;
  } else {
    result += `\n\n[Yeh poori list hai — total ${total} items]`;
  }
  return { text: result, hasMore: remaining > 0, offset, nextOffset: offset + page.length, total };
}

// ── Strip ALL action JSON blocks from reply text ──────────────────────────────
function stripActionBlocks(text) {
  // Strip {"actions":[...]} blocks
  text = text.replace(/\{"actions"\s*:\s*\[[\s\S]*?\]\s*\}/g, '').trim();
  // Strip single action JSON blocks
  let depth = 0, inBlock = false, blockStart = -1;
  let stripped = '';
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '{') {
      if (depth === 0) blockStart = i;
      depth++;
      inBlock = true;
    } else if (text[i] === '}' && inBlock) {
      depth--;
      if (depth === 0) {
        const block = text.slice(blockStart, i + 1);
        try { const obj = JSON.parse(block); if (obj && obj.action) { inBlock = false; blockStart = -1; continue; } } catch {}
        stripped += block;
        inBlock = false; blockStart = -1;
      }
    } else if (!inBlock || depth === 0) {
      stripped += text[i];
    }
  }
  return stripped.trim();
}

// ── AI Firestore Action Executor ──────────────────────────────────────────────
async function executeFirestoreAction(action, db) {
  const aiRef = { uid: 'ai-agent', name: 'AI Assistant', at: admin.firestore.Timestamp.now() };

  switch (action.action) {

    // ════════════════════════════════════════════════════════════════════════
    // DEMAND ITEMS
    // ════════════════════════════════════════════════════════════════════════

    case 'add_demand_item': {
      const name = (action.name || '').trim();
      if (!name) return { success: false, message: 'Item ka naam zaroor chahiye' };

      // Resolve categoryId: support categoryName OR direct categoryId
      let categoryId = null;
      if (action.categoryName !== undefined && action.categoryName !== null) {
        const cn = (action.categoryName || '').trim();
        if (cn && cn.toLowerCase() !== 'general') {
          const catSnap = await db.collection('categories').get();
          const catMatch = catSnap.docs.find(d => (d.data().name || '').toLowerCase() === cn.toLowerCase());
          categoryId = catMatch ? catMatch.id : null;
          if (!catMatch) {
            const available = catSnap.docs.map(d => d.data().name).join(', ');
            return { success: false, message: `"${cn}" naam ki category nahi mili. Available: ${available || '(none)'}` };
          }
        }
      } else if (action.categoryId && action.categoryId !== 'general') {
        categoryId = String(action.categoryId).trim();
      }

      const status = ['pending', 'available', 'deferred', 'urgent'].includes(action.status)
        ? action.status : 'pending';
      const docRef = await db.collection('demandItems').add({
        name,
        quantity: String(action.quantity || action.qty || ''),
        unit: action.unit || 'Piece',
        packContents: (action.packContents || '').trim(),
        notes: action.notes || '',
        status,
        isUrgent: status === 'urgent',
        barcode: action.barcode || '',
        categoryId,
        sellPrice: Number(action.sellPrice) || 200.0,
        costPrice: action.costPrice != null ? Number(action.costPrice) : null,
        wholesalePrice: action.wholesalePrice != null ? Number(action.wholesalePrice) : null,
        stock: Number(action.stock) || 500,
        addedBy: aiRef,
        lastEditedBy: aiRef,
        createdAt: admin.firestore.Timestamp.now(),
      });
      const catNote = categoryId ? ` [category ID: ${categoryId}]` : '';
      return { success: true, message: `✅ "${name}" demand list mein add ho gaya${catNote}`, docId: docRef.id };
    }

    case 'search_demand_items': {
      // Direct Firestore search — finds items even if not shown in AI context (due to pagination).
      const query = (action.query || action.name || '').trim().toLowerCase();
      const statusFilter = (action.status || '').trim().toLowerCase();
      if (!query && !statusFilter) return { success: false, message: 'Search query ya status zaroor chahiye' };

      const snap = await db.collection('demandItems').get();
      let results = snap.docs.map(d => ({ id: d.id, ...d.data() }));

      if (query) {
        // Primary: substring match on name
        let nameMatches = results.filter(d => (d.name || '').toLowerCase().includes(query));
        // Fallback: check if any word in the item name starts with the query (for partial/typo)
        if (nameMatches.length === 0) {
          nameMatches = results.filter(d =>
            (d.name || '').toLowerCase().split(/\s+/).some(w => w.startsWith(query))
          );
        }
        results = nameMatches;
      }
      if (statusFilter && ['pending','available','deferred','urgent'].includes(statusFilter)) {
        results = results.filter(d => (d.status || 'pending') === statusFilter);
      }

      if (results.length === 0) {
        const hint = query ? `"${query}" naam ka koi item nahi mila` : `Koi ${statusFilter} item nahi mila`;
        return { success: false, message: hint, results: [] };
      }

      const formatted = results.slice(0, 50).map(d => {
        const qty = d.quantity ? `${d.quantity} ${d.unit || ''}`.trim() : '';
        const pack = d.packContents ? ` (${d.packContents} per ${d.unit || 'unit'})` : '';
        return `• ${d.name} — Status: ${d.status || 'pending'} | Qty: ${qty}${pack} | Sell: Rs ${d.sellPrice || 200}`;
      });
      const total = results.length;
      const msg = `✅ ${total} item${total === 1 ? '' : 's'} mila:\n${formatted.join('\n')}${total > 50 ? `\n... (${total - 50} aur hain)` : ''}`;
      return { success: true, message: msg, results: results.slice(0, 50).map(d => ({
        name: d.name, status: d.status, qty: d.quantity, unit: d.unit, packContents: d.packContents
      }))};
    }

    case 'update_demand_status': {
      const name = (action.name || '').trim().toLowerCase();
      const newStatus = (action.status || '').trim().toLowerCase();
      if (!name) return { success: false, message: 'Item ka naam zaroor chahiye' };
      if (!['pending', 'available', 'deferred', 'urgent'].includes(newStatus))
        return { success: false, message: `"${action.status}" valid status nahi — pending/available/deferred/urgent mein se hona chahiye` };
      const snap = await db.collection('demandItems').get();
      const matches = snap.docs.filter(d => (d.data().name || '').toLowerCase().includes(name));
      if (matches.length === 0) return { success: false, message: `"${action.name}" naam ka koi item nahi mila` };
      if (matches.length > 5) return { success: false, message: `"${action.name}" se ${matches.length} items match hote hain — zyada specific naam batao` };
      const batch = db.batch();
      matches.forEach(d => batch.update(d.ref, {
        status: newStatus,
        isUrgent: newStatus === 'urgent',
        lastEditedBy: aiRef,
      }));
      await batch.commit();
      return { success: true, message: `✅ ${matches.length} item(s) ka status "${newStatus}" ho gaya`, statusChange: newStatus };
    }

    case 'delete_demand_item': {
      const name = (action.name || '').trim().toLowerCase();
      if (!name) return { success: false, message: 'Item ka naam zaroor chahiye' };
      const snap = await db.collection('demandItems').get();
      const matches = snap.docs.filter(d => (d.data().name || '').toLowerCase().includes(name));
      if (matches.length === 0) return { success: false, message: `"${action.name}" naam ka koi item nahi mila` };
      if (matches.length > 3) return { success: false, message: `"${action.name}" se ${matches.length} items match hote hain — zyada specific naam batao` };
      const batch = db.batch();
      matches.forEach(d => batch.delete(d.ref));
      await batch.commit();
      return { success: true, message: `✅ "${action.name}" (${matches.length} item) delete ho gaya` };
    }

    case 'update_demand_item': {
      const name = (action.name || '').trim().toLowerCase();
      if (!name) return { success: false, message: 'Item ka naam zaroor chahiye' };
      const snap = await db.collection('demandItems').get();
      const matches = snap.docs.filter(d => (d.data().name || '').toLowerCase().includes(name));
      if (matches.length === 0) return { success: false, message: `"${action.name}" naam ka koi item nahi mila` };
      if (matches.length > 3) return { success: false, message: `Zyada matches mile — specific naam batao` };
      const updates = { lastEditedBy: aiRef };
      if (action.newName) updates.name = action.newName.trim();
      if (action.quantity !== undefined) updates.quantity = String(action.quantity);
      if (action.qty !== undefined) updates.quantity = String(action.qty);
      if (action.unit) updates.unit = action.unit;
      if (action.packContents !== undefined) updates.packContents = (action.packContents || '').trim();
      if (action.notes !== undefined) updates.notes = action.notes;
      if (action.barcode !== undefined) updates.barcode = action.barcode;
      if (action.status) { updates.status = action.status; updates.isUrgent = action.status === 'urgent'; }
      // Support categoryName (resolve to ID) OR direct categoryId
      if (action.categoryName !== undefined) {
        const cn = (action.categoryName || '').trim();
        if (!cn || cn.toLowerCase() === 'general') {
          updates.categoryId = null;
        } else {
          const catSnap2 = await db.collection('categories').get();
          const catMatch = catSnap2.docs.find(d => (d.data().name || '').toLowerCase() === cn.toLowerCase());
          updates.categoryId = catMatch ? catMatch.id : null;
        }
      } else if (action.categoryId !== undefined) {
        updates.categoryId = action.categoryId === 'general' ? null : String(action.categoryId).trim();
      }
      // Pricing + inventory fields
      if (action.sellPrice !== undefined) updates.sellPrice = Number(action.sellPrice) || 200.0;
      if (action.costPrice !== undefined) updates.costPrice = action.costPrice !== null ? Number(action.costPrice) : null;
      if (action.wholesalePrice !== undefined) updates.wholesalePrice = action.wholesalePrice !== null ? Number(action.wholesalePrice) : null;
      if (action.stock !== undefined) updates.stock = Number(action.stock) || 500;
      const batch = db.batch();
      matches.forEach(d => batch.update(d.ref, updates));
      await batch.commit();
      return { success: true, message: `✅ "${action.name}" update ho gaya` };
    }

    // ════════════════════════════════════════════════════════════════════════
    // BULK ACTIONS — new
    // ════════════════════════════════════════════════════════════════════════

    // Assign a category to ALL demand items that match an optional name filter
    // action = { action:'bulk_assign_category', categoryId:'...', nameFilter:'rice' (optional) }
    // If nameFilter is omitted → assign to ALL items
    case 'bulk_assign_category': {
      const rawCatId = (action.categoryId || '').trim();
      if (!rawCatId) return { success: false, message: 'categoryId zaroor chahiye' };
      const categoryId = rawCatId === 'general' ? null : rawCatId;
      const nameFilter = (action.nameFilter || '').trim().toLowerCase();

      // Validate category exists (unless resetting to general)
      if (categoryId) {
        const catDoc = await db.collection('categories').doc(rawCatId).get();
        if (!catDoc.exists) return { success: false, message: `Category ID "${rawCatId}" exist nahi karti — pehle categories list check karo` };
      }

      const snap = await db.collection('demandItems').get();
      const targets = nameFilter
        ? snap.docs.filter(d => (d.data().name || '').toLowerCase().includes(nameFilter))
        : snap.docs;

      if (targets.length === 0)
        return { success: false, message: nameFilter ? `"${nameFilter}" se koi item nahi mila` : 'Koi demand item nahi hai' };

      const catLabel = categoryId ? `ID: ${categoryId}` : 'General (default)';
      // Batch write in chunks of 500 (Firestore limit)
      for (const chunk of chunkArray(targets, 500)) {
        const batch = db.batch();
        chunk.forEach(d => batch.update(d.ref, { categoryId, lastEditedBy: aiRef }));
        await batch.commit();
      }
      const filterNote = nameFilter ? ` (filter: "${nameFilter}")` : ' (saare items)';
      return { success: true, message: `✅ ${targets.length} items ko category "${catLabel}" assign ho gayi${filterNote}` };
    }

    // ── NEW: bulk_assign_category_by_name — resolve category name → ID automatically
    // Fixes multi-turn issue: AI doesn't need to know Firestore ID, just the name.
    // action = { action:'bulk_assign_category_by_name', categoryName:'Ration', nameFilter:'rice' (optional) }
    case 'bulk_assign_category_by_name': {
      const catName = (action.categoryName || '').trim();
      if (!catName) return { success: false, message: 'categoryName zaroor chahiye (e.g. "Ration")' };
      if (catName.toLowerCase() === 'general') {
        // Resetting to general
        const snap2 = await db.collection('demandItems').get();
        const nf2 = (action.nameFilter || '').trim().toLowerCase();
        const t2 = nf2 ? snap2.docs.filter(d => (d.data().name || '').toLowerCase().includes(nf2)) : snap2.docs;
        for (const chunk of chunkArray(t2, 500)) {
          const batch = db.batch();
          chunk.forEach(d => batch.update(d.ref, { categoryId: null, lastEditedBy: aiRef }));
          await batch.commit();
        }
        return { success: true, message: `✅ ${t2.length} items General category mein reset ho gaye` };
      }
      // Find category by name (case-insensitive)
      const catSnap = await db.collection('categories').get();
      const catDoc = catSnap.docs.find(d =>
        (d.data().name || '').toLowerCase() === catName.toLowerCase()
      );
      if (!catDoc) {
        const available = catSnap.docs.map(d => d.data().name).join(', ');
        return { success: false, message: `"${catName}" naam ki category nahi mili. Available: ${available || '(none)'}` };
      }
      const resolvedId = catDoc.id;
      const nameFilter = (action.nameFilter || '').trim().toLowerCase();
      const snap = await db.collection('demandItems').get();
      const targets = nameFilter
        ? snap.docs.filter(d => (d.data().name || '').toLowerCase().includes(nameFilter))
        : snap.docs;
      if (targets.length === 0)
        return { success: false, message: nameFilter ? `"${nameFilter}" se koi item nahi mila` : 'Koi demand item nahi hai' };
      for (const chunk of chunkArray(targets, 500)) {
        const batch = db.batch();
        chunk.forEach(d => batch.update(d.ref, { categoryId: resolvedId, lastEditedBy: aiRef }));
        await batch.commit();
      }
      const filterNote = nameFilter ? ` (filter: "${nameFilter}")` : ' (saare items)';
      return { success: true, message: `✅ ${targets.length} items ko category "${catName}" (ID: ${resolvedId}) assign ho gayi${filterNote}` };
    }

    // Add multiple demand items in one shot
    // action = { action:'bulk_add_demand_items', items:[{name,qty,unit,notes,status,categoryId},...] }
    case 'bulk_add_demand_items': {
      const items = Array.isArray(action.items) ? action.items : [];
      if (items.length === 0) return { success: false, message: 'items array khali hai' };
      if (items.length > 500) return { success: false, message: 'Ek baar mein max 500 items add ho sakte hain' };

      let added = 0, failed = 0, failedNames = [];
      for (const chunk of chunkArray(items, 500)) {
        const batch = db.batch();
        for (const item of chunk) {
          const name = (item.name || '').trim();
          if (!name) { failed++; failedNames.push('(empty name)'); continue; }
          const catId = item.categoryId && item.categoryId !== 'general'
            ? String(item.categoryId).trim() : null;
          const itemStatus = ['pending', 'available', 'deferred', 'urgent'].includes(item.status)
            ? item.status : 'pending';
          const newRef = db.collection('demandItems').doc();
          batch.set(newRef, {
            name,
            quantity: String(item.quantity || item.qty || ''),
            unit: item.unit || 'Piece',
            packContents: (item.packContents || '').trim(),
            notes: item.notes || '',
            status: itemStatus,
            isUrgent: itemStatus === 'urgent',
            barcode: item.barcode || '',
            categoryId: catId,
            sellPrice: Number(item.sellPrice) || 200.0,
            costPrice: item.costPrice != null ? Number(item.costPrice) : null,
            wholesalePrice: item.wholesalePrice != null ? Number(item.wholesalePrice) : null,
            stock: Number(item.stock) || 500,
            addedBy: aiRef,
            lastEditedBy: aiRef,
            createdAt: admin.firestore.Timestamp.now(),
          });
          added++;
        }
        await batch.commit();
      }
      const failNote = failed > 0 ? ` | ❌ ${failed} fail (naam nahi tha)` : '';
      return { success: added > 0, message: `✅ ${added} items demand list mein add ho gaye${failNote}` };
    }

    // Bulk status update — update status of all items matching a name filter
    // action = { action:'bulk_update_status', nameFilter:'...', status:'available', categoryId:'...' (optional) }
    case 'bulk_update_status': {
      const newStatus = (action.status || '').trim().toLowerCase();
      if (!['pending', 'available', 'deferred', 'urgent'].includes(newStatus))
        return { success: false, message: `"${action.status}" valid status nahi` };

      const nameFilter = (action.nameFilter || '').trim().toLowerCase();
      let catFilter = (action.categoryId || '').trim();

      // Resolve categoryName → categoryId
      if (!catFilter && action.categoryName) {
        const cn = (action.categoryName || '').trim();
        if (cn.toLowerCase() === 'general') {
          catFilter = 'general';
        } else {
          const catSnap = await db.collection('categories').get();
          const catDoc = catSnap.docs.find(d => (d.data().name || '').toLowerCase() === cn.toLowerCase());
          if (!catDoc) {
            const available = catSnap.docs.map(d => d.data().name).join(', ');
            return { success: false, message: `"${cn}" naam ki category nahi mili. Available: ${available || '(none)'}` };
          }
          catFilter = catDoc.id;
        }
      }

      const snap = await db.collection('demandItems').get();
      let targets = snap.docs;
      if (nameFilter) targets = targets.filter(d => (d.data().name || '').toLowerCase().includes(nameFilter));
      if (catFilter && catFilter !== 'general') targets = targets.filter(d => (d.data().categoryId || '') === catFilter);
      if (catFilter === 'general') targets = targets.filter(d => !d.data().categoryId);

      if (targets.length === 0) return { success: false, message: 'Koi matching item nahi mila' };

      for (const chunk of chunkArray(targets, 500)) {
        const batch = db.batch();
        chunk.forEach(d => batch.update(d.ref, {
          status: newStatus,
          isUrgent: newStatus === 'urgent',
          lastEditedBy: aiRef,
        }));
        await batch.commit();
      }
      return { success: true, message: `✅ ${targets.length} items ka status "${newStatus}" ho gaya`, statusChange: newStatus };
    }

    // Bulk delete demand items by name filter or category
    // action = { action:'bulk_delete_demand_items', nameFilter:'rice', categoryId:'...' (optional) }
    // WARNING: requires at least nameFilter OR categoryId — won't delete ALL without filter
    case 'bulk_delete_demand_items': {
      const nameFilter = (action.nameFilter || '').trim().toLowerCase();
      const statusFilter = (action.status || '').trim().toLowerCase();
      let catFilter = (action.categoryId || '').trim();

      // Resolve categoryName → categoryId
      if (!catFilter && action.categoryName) {
        const cn = (action.categoryName || '').trim();
        if (cn.toLowerCase() === 'general') {
          catFilter = 'general';
        } else {
          const catSnap = await db.collection('categories').get();
          const catDoc = catSnap.docs.find(d => (d.data().name || '').toLowerCase() === cn.toLowerCase());
          if (!catDoc) {
            const available = catSnap.docs.map(d => d.data().name).join(', ');
            return { success: false, message: `"${cn}" naam ki category nahi mili. Available: ${available || '(none)'}` };
          }
          catFilter = catDoc.id;
        }
      }

      if (!nameFilter && !catFilter && !statusFilter) {
        return { success: false, message: '⚠️ Safety: nameFilter, categoryId/categoryName, ya status mein se koi ek zaroor chahiye — sab kuch delete karna allowed nahi hai' };
      }

      const snap = await db.collection('demandItems').get();
      let targets = snap.docs;
      if (nameFilter) targets = targets.filter(d => (d.data().name || '').toLowerCase().includes(nameFilter));
      if (catFilter && catFilter !== 'general') targets = targets.filter(d => (d.data().categoryId || '') === catFilter);
      if (catFilter === 'general') targets = targets.filter(d => !d.data().categoryId);
      if (statusFilter) targets = targets.filter(d => (d.data().status || '') === statusFilter);

      if (targets.length === 0) return { success: false, message: 'Koi matching item nahi mila — kuch delete nahi hua' };

      for (const chunk of chunkArray(targets, 500)) {
        const batch = db.batch();
        chunk.forEach(d => batch.delete(d.ref));
        await batch.commit();
      }
      return { success: true, message: `✅ ${targets.length} items delete ho gaye` };
    }

    // ════════════════════════════════════════════════════════════════════════
    // SUPPLIERS
    // ════════════════════════════════════════════════════════════════════════

    case 'add_supplier': {
      const name = (action.name || '').trim();
      if (!name) return { success: false, message: 'Supplier ka naam zaroor chahiye' };
      await db.collection('suppliers').add({
        name,
        company: action.company || '',
        productsSupplied: action.productsSupplied || '',
        whatsappNumber: action.whatsappNumber || '',
        phoneNumber: action.phoneNumber || '',
        additionalNumbers: [],
        addedBy: aiRef,
        lastEditedBy: aiRef,
      });
      return { success: true, message: `✅ "${name}" supplier list mein add ho gaya` };
    }

    case 'update_supplier': {
      const name = (action.name || '').trim().toLowerCase();
      if (!name) return { success: false, message: 'Supplier ka naam zaroor chahiye' };
      const snap = await db.collection('suppliers').get();
      const matches = snap.docs.filter(d => (d.data().name || '').toLowerCase().includes(name));
      if (matches.length === 0) return { success: false, message: `"${action.name}" naam ka supplier nahi mila` };
      if (matches.length > 2) return { success: false, message: `Zyada matches — specific naam batao` };
      const updates = { lastEditedBy: aiRef };
      if (action.newName) updates.name = action.newName.trim();
      if (action.company !== undefined) updates.company = action.company;
      if (action.productsSupplied !== undefined) updates.productsSupplied = action.productsSupplied;
      if (action.whatsappNumber !== undefined) updates.whatsappNumber = action.whatsappNumber;
      if (action.phoneNumber !== undefined) updates.phoneNumber = action.phoneNumber;
      const batch = db.batch();
      matches.forEach(d => batch.update(d.ref, updates));
      await batch.commit();
      return { success: true, message: `✅ Supplier "${action.name}" update ho gaya` };
    }

    case 'delete_supplier': {
      const name = (action.name || '').trim().toLowerCase();
      if (!name) return { success: false, message: 'Supplier ka naam zaroor chahiye' };
      const snap = await db.collection('suppliers').get();
      const matches = snap.docs.filter(d => (d.data().name || '').toLowerCase().includes(name));
      if (matches.length === 0) return { success: false, message: `"${action.name}" naam ka supplier nahi mila` };
      if (matches.length > 3) return { success: false, message: `Zyada matches mile — specific naam batao` };
      const batch = db.batch();
      matches.forEach(d => batch.delete(d.ref));
      await batch.commit();
      return { success: true, message: `✅ Supplier "${action.name}" delete ho gaya` };
    }

    // ════════════════════════════════════════════════════════════════════════
    // CUSTOMERS
    // ════════════════════════════════════════════════════════════════════════

    case 'add_customer': {
      const name = (action.name || '').trim();
      if (!name) return { success: false, message: 'Customer ka naam zaroor chahiye' };
      const phone = action.phone || action.whatsappNumber || '';
      await db.collection('customers').add({
        name,
        phone,
        whatsappNumber: action.whatsappNumber || phone,
        address: action.address || '',
        notes: action.notes || '',
        addedBy: aiRef,
        lastEditedBy: aiRef,
        createdAt: admin.firestore.Timestamp.now(),
      });
      return { success: true, message: `✅ "${name}" customer list mein add ho gaya` };
    }

    case 'update_customer': {
      const name = (action.name || '').trim().toLowerCase();
      if (!name) return { success: false, message: 'Customer ka naam zaroor chahiye' };
      const snap = await db.collection('customers').get();
      const matches = snap.docs.filter(d => (d.data().name || '').toLowerCase().includes(name));
      if (matches.length === 0) return { success: false, message: `"${action.name}" naam ka customer nahi mila` };
      if (matches.length > 2) return { success: false, message: `Zyada matches — specific naam batao` };
      const updates = { lastEditedBy: aiRef };
      if (action.newName) updates.name = action.newName.trim();
      if (action.phone !== undefined) updates.phone = action.phone;
      if (action.whatsappNumber !== undefined) updates.whatsappNumber = action.whatsappNumber;
      if (action.address !== undefined) updates.address = action.address;
      if (action.notes !== undefined) updates.notes = action.notes;
      const batch = db.batch();
      matches.forEach(d => batch.update(d.ref, updates));
      await batch.commit();
      return { success: true, message: `✅ Customer "${action.name}" update ho gaya` };
    }

    case 'delete_customer': {
      const name = (action.name || '').trim().toLowerCase();
      if (!name) return { success: false, message: 'Customer ka naam zaroor chahiye' };
      const snap = await db.collection('customers').get();
      const matches = snap.docs.filter(d => (d.data().name || '').toLowerCase().includes(name));
      if (matches.length === 0) return { success: false, message: `"${action.name}" naam ka customer nahi mila` };
      if (matches.length > 3) return { success: false, message: `Zyada matches — specific naam batao` };
      const batch = db.batch();
      matches.forEach(d => batch.delete(d.ref));
      await batch.commit();
      return { success: true, message: `✅ Customer "${action.name}" delete ho gaya` };
    }

    // ════════════════════════════════════════════════════════════════════════
    // UDHAAR
    // ════════════════════════════════════════════════════════════════════════

    case 'settle_udhaar': {
      const name = (action.name || '').trim().toLowerCase();
      if (!name) return { success: false, message: 'Person ka naam zaroor chahiye' };
      const snap = await db.collection('udhaarEntries').where('status', '==', 'pending').get();
      const matches = snap.docs.filter(d => (d.data().personName || '').toLowerCase().includes(name));
      if (matches.length === 0) return { success: false, message: `"${action.name}" ka koi pending udhaar nahi mila` };
      const batch = db.batch();
      matches.forEach(d => batch.update(d.ref, {
        status: 'settled', settledAt: admin.firestore.Timestamp.now(), lastEditedBy: aiRef,
      }));
      await batch.commit();
      return { success: true, message: `✅ "${action.name}" ka udhaar (${matches.length} entries) settle ho gaya` };
    }

    case 'add_udhaar': {
      const personName = (action.personName || action.name || '').trim();
      const amount = Number(action.amount);
      if (!personName || !amount) return { success: false, message: 'Person ka naam aur amount zaroor chahiye' };
      const type = action.type === 'received' ? 'received' : 'given';
      await db.collection('udhaarEntries').add({
        personName,
        amount,
        type,
        status: 'pending',
        notes: action.notes || '',
        addedBy: aiRef,
        lastEditedBy: aiRef,
        createdAt: admin.firestore.Timestamp.now(),
      });
      return { success: true, message: `✅ ${personName} ka udhaar Rs ${amount} (${type === 'given' ? 'dena hai' : 'lena hai'}) add ho gaya` };
    }

    case 'delete_udhaar': {
      const name = (action.name || action.personName || '').trim().toLowerCase();
      if (!name) return { success: false, message: 'Person ka naam zaroor chahiye' };
      const snap = await db.collection('udhaarEntries').where('status', '==', 'pending').get();
      const matches = snap.docs.filter(d => (d.data().personName || '').toLowerCase().includes(name));
      if (matches.length === 0) return { success: false, message: `"${name}" ka koi pending udhaar nahi mila (settled records protected hain)` };
      if (matches.length > 3) return { success: false, message: `Zyada matches — specific naam batao` };
      const batch = db.batch();
      matches.forEach(d => batch.delete(d.ref));
      await batch.commit();
      return { success: true, message: `✅ "${name}" ke ${matches.length} pending udhaar records delete ho gaye` };
    }

    case 'update_udhaar': {
      const name = (action.name || action.personName || '').trim().toLowerCase();
      if (!name) return { success: false, message: 'Person ka naam zaroor chahiye' };
      const snap = await db.collection('udhaarEntries').where('status', '==', 'pending').get();
      const matches = snap.docs.filter(d => (d.data().personName || '').toLowerCase().includes(name));
      if (matches.length === 0) return { success: false, message: `"${action.name || action.personName}" ka koi pending udhaar nahi mila` };
      if (matches.length > 2) return { success: false, message: `Zyada matches — specific naam batao` };
      const updates = { lastEditedBy: aiRef };
      if (action.amount !== undefined) updates.amount = Number(action.amount);
      if (action.type !== undefined) updates.type = action.type === 'received' ? 'received' : 'given';
      if (action.notes !== undefined) updates.notes = action.notes;
      const batch = db.batch();
      matches.forEach(d => batch.update(d.ref, updates));
      await batch.commit();
      return { success: true, message: `✅ "${action.name || action.personName}" ka udhaar update ho gaya` };
    }

    // ════════════════════════════════════════════════════════════════════════
    // CATEGORIES
    // ════════════════════════════════════════════════════════════════════════

    case 'add_category': {
      const name = (action.name || '').trim();
      if (!name) return { success: false, message: 'Category ka naam zaroor chahiye' };
      const existing = await db.collection('categories').get();
      const dup = existing.docs.find(d => (d.data().name || '').toLowerCase() === name.toLowerCase());
      if (dup) return { success: false, message: `"${name}" category pehle se exist karti hai (ID: ${dup.id})` };
      const ref = await db.collection('categories').add({ name });
      return { success: true, message: `✅ Category "${name}" add ho gayi (ID: ${ref.id})`, categoryId: ref.id };
    }

    case 'update_category': {
      const catId = (action.id || '').trim();
      const catNameParam = (action.name || '').trim(); // fallback: find by name
      const newName = (action.newName || '').trim();
      if (!newName) return { success: false, message: 'Naya naam zaroor chahiye' };
      if (catId === 'general' || catNameParam.toLowerCase() === 'general')
        return { success: false, message: 'General category update nahi ho sakti' };
      // Resolve: prefer ID, fall back to name lookup
      let resolvedRef = null;
      if (catId) {
        const docRef = db.collection('categories').doc(catId);
        const docSnap = await docRef.get();
        if (docSnap.exists) resolvedRef = docRef;
      }
      if (!resolvedRef && catNameParam) {
        const catSnap = await db.collection('categories').get();
        const found = catSnap.docs.find(d => (d.data().name || '').toLowerCase() === catNameParam.toLowerCase());
        if (found) resolvedRef = found.ref;
      }
      if (!resolvedRef) return { success: false, message: `Category "${catId || catNameParam}" nahi mili — categories list check karo` };
      await resolvedRef.update({ name: newName });
      return { success: true, message: `✅ Category update ho gayi: "${newName}"` };
    }

    case 'delete_category': {
      const catId = (action.id || '').trim();
      const catNameParam = (action.name || '').trim();
      if (!catId && !catNameParam) return { success: false, message: 'Category ID ya naam zaroor chahiye' };
      if (catId === 'general' || catNameParam.toLowerCase() === 'general')
        return { success: false, message: 'General category delete nahi ho sakti' };
      // Resolve: prefer ID, fall back to name lookup
      let resolvedRef = null, resolvedName = '';
      if (catId) {
        const docRef = db.collection('categories').doc(catId);
        const docSnap = await docRef.get();
        if (docSnap.exists) { resolvedRef = docRef; resolvedName = docSnap.data().name || catId; }
      }
      if (!resolvedRef && catNameParam) {
        const catSnap = await db.collection('categories').get();
        const found = catSnap.docs.find(d => (d.data().name || '').toLowerCase() === catNameParam.toLowerCase());
        if (found) { resolvedRef = found.ref; resolvedName = found.data().name || catNameParam; }
      }
      if (!resolvedRef) return { success: false, message: `Category "${catId || catNameParam}" nahi mili` };
      await resolvedRef.delete();
      return { success: true, message: `✅ Category "${resolvedName}" delete ho gayi` };
    }

    // ════════════════════════════════════════════════════════════════════════
    // PRICING ANALYTICS (read-only — no Firestore writes)
    // Returns per-category sell/cost/wholesale totals and profit margins
    // action = { action:'get_pricing_analytics', statusFilter:'all'|'pending'|'urgent'|'pending_urgent'|'available'|'deferred' }
    case 'get_pricing_analytics': {
      const sf = (action.statusFilter || 'all').trim().toLowerCase();
      let items = allDemands.filter(d => (d.name || '').trim().length > 0);
      if (sf === 'pending') items = items.filter(d => d.status === 'pending');
      else if (sf === 'urgent') items = items.filter(d => d.status === 'urgent');
      else if (sf === 'pending_urgent') items = items.filter(d => d.status === 'pending' || d.status === 'urgent');
      else if (sf === 'available') items = items.filter(d => d.status === 'available');
      else if (sf === 'deferred') items = items.filter(d => d.status === 'deferred');

      if (items.length === 0) {
        return { success: true, message: `(Koi items nahi mile filter: ${sf})` };
      }

      // Per-category breakdown
      const catGroups = {};
      items.forEach(d => {
        const catId = d.categoryId || 'general';
        const catName = catMap[catId] || 'General';
        if (!catGroups[catName]) catGroups[catName] = [];
        catGroups[catName].push(d);
      });

      const totalSell = items.reduce((s, d) => s + d.sellPrice, 0);
      const costItems = items.filter(d => d.costPrice !== null);
      const totalCost = costItems.length > 0 ? costItems.reduce((s, d) => s + (d.costPrice || 0), 0) : null;
      const profit = totalCost !== null ? totalSell - totalCost : null;
      const marginPct = profit !== null && totalSell > 0 ? (profit / totalSell * 100).toFixed(1) : null;

      let report = `📊 Pricing Analytics (${sf})\n`;
      report += `Total items: ${items.length}\n`;
      report += `────────────────────────────\n`;
      report += `💰 Total Sell  : Rs ${totalSell.toFixed(0)}\n`;
      if (totalCost !== null) {
        report += `🛒 Total Cost  : Rs ${totalCost.toFixed(0)}\n`;
        report += `📈 Profit      : Rs ${profit.toFixed(0)} (${marginPct}% margin)\n`;
      } else {
        report += `🛒 Cost prices : (not set)\n`;
      }
      report += `\n📂 By Category:\n`;

      Object.entries(catGroups).forEach(([catName, catItems]) => {
        const catSell = catItems.reduce((s, d) => s + d.sellPrice, 0);
        const catCostItems = catItems.filter(d => d.costPrice !== null);
        const catCost = catCostItems.length > 0 ? catCostItems.reduce((s, d) => s + (d.costPrice || 0), 0) : null;
        const catProfit = catCost !== null ? catSell - catCost : null;
        const catMargin = catProfit !== null && catSell > 0 ? (catProfit / catSell * 100).toFixed(1) : null;
        const noCost = catItems.filter(d => d.costPrice === null).length;

        report += `\n  ▪ ${catName} (${catItems.length} items)\n`;
        report += `    Sell: Rs ${catSell.toFixed(0)}`;
        if (catCost !== null) report += ` | Cost: Rs ${catCost.toFixed(0)} | Profit: Rs ${catProfit.toFixed(0)} (${catMargin}%)`;
        if (noCost > 0) report += ` | ${noCost} without cost price`;
        report += '\n';
      });

      return { success: true, message: report };
    }

    // ════════════════════════════════════════════════════════════════════════
    // PRICING MANAGEMENT
    // ════════════════════════════════════════════════════════════════════════

    // Search demand items by price range
    // action = { action:'search_by_price', priceField:'sellPrice'|'costPrice'|'wholesalePrice',
    //            minPrice:100, maxPrice:500, status:'pending' (optional) }
    case 'search_by_price': {
      const validFields = ['sellPrice', 'costPrice', 'wholesalePrice'];
      const priceField = validFields.includes(action.priceField)
        ? action.priceField : 'sellPrice';
      const minPrice = action.minPrice !== undefined ? Number(action.minPrice) : null;
      const maxPrice = action.maxPrice !== undefined ? Number(action.maxPrice) : null;
      const statusFilter = (action.status || '').trim().toLowerCase();

      if (minPrice === null && maxPrice === null) {
        return { success: false, message: 'minPrice ya maxPrice mein se koi ek zaroor chahiye' };
      }

      const snap = await db.collection('demandItems').get();
      let results = [];
      snap.docs.forEach(d => {
        const data = d.data();
        const name = (data.name || '').trim();
        if (!name) return;
        const fieldVal = Number(data[priceField]) || 0;
        if (minPrice !== null && fieldVal < minPrice) return;
        if (maxPrice !== null && fieldVal > maxPrice) return;
        if (statusFilter && ['pending','available','deferred','urgent'].includes(statusFilter)
            && (data.status || 'pending') !== statusFilter) return;
        results.push({ name, price: fieldVal, status: data.status || 'pending', id: d.id });
      });

      if (results.length === 0) {
        const rangeDesc = minPrice !== null && maxPrice !== null
          ? `Rs ${minPrice}–${maxPrice}` : minPrice !== null ? `Rs ${minPrice}+` : `Rs 0–${maxPrice}`;
        return { success: true, message: `(${priceField} ${rangeDesc} range mein koi item nahi mila)` };
      }

      results.sort((a, b) => a.price - b.price);
      const shown = results.slice(0, 100);
      const list = shown.map((d, i) =>
        `${i+1}. ${d.name} — Rs ${d.price} (${d.status})`
      ).join('\n');
      const rangeStr = minPrice !== null && maxPrice !== null
        ? `Rs ${minPrice}–${maxPrice}` : minPrice !== null ? `Rs ${minPrice}+` : `Rs 0–${maxPrice}`;
      const more = results.length > 100 ? `\n\n(${results.length - 100} aur items hain)` : '';
      return {
        success: true,
        message: `✅ ${results.length} items mile (${priceField} ${rangeStr}):\n\n${list}${more}`,
      };
    }

    // Bulk update prices for matching items
    // action = { action:'bulk_update_price', sellPrice:250, costPrice:200, wholesalePrice:220,
    //            nameFilter:'rice' (optional), categoryId:'...' (optional),
    //            status:'pending' (optional), confirmAll:true (required if no filter) }
    case 'bulk_update_price': {
      const nameFilter = (action.nameFilter || '').trim().toLowerCase();
      const catFilter = (action.categoryId || '').trim();
      const statusFilter = (action.status || '').trim().toLowerCase();

      if (!nameFilter && !catFilter && !statusFilter && !action.confirmAll) {
        return {
          success: false,
          message: '⚠️ Safety: nameFilter, categoryId, status, ya confirmAll:true zaroor chahiye — bulk price update ke liye confirm karo',
        };
      }

      const snap = await db.collection('demandItems').get();
      let targets = snap.docs;
      if (nameFilter) targets = targets.filter(d => (d.data().name || '').toLowerCase().includes(nameFilter));
      if (catFilter && catFilter !== 'general') targets = targets.filter(d => (d.data().categoryId || '') === catFilter);
      if (catFilter === 'general') targets = targets.filter(d => !d.data().categoryId);
      if (statusFilter && ['pending','available','deferred','urgent'].includes(statusFilter))
        targets = targets.filter(d => (d.data().status || 'pending') === statusFilter);

      if (targets.length === 0) return { success: false, message: 'Koi matching item nahi mila' };

      const updates = { lastEditedBy: aiRef };
      const priceInfo = [];
      if (action.sellPrice !== undefined) {
        updates.sellPrice = Number(action.sellPrice) || 200.0;
        priceInfo.push(`Sell: Rs ${updates.sellPrice}`);
      }
      if (action.costPrice !== undefined) {
        updates.costPrice = action.costPrice !== null ? Number(action.costPrice) : null;
        priceInfo.push(`Cost: Rs ${updates.costPrice ?? 'removed'}`);
      }
      if (action.wholesalePrice !== undefined) {
        updates.wholesalePrice = action.wholesalePrice !== null ? Number(action.wholesalePrice) : null;
        priceInfo.push(`Wholesale: Rs ${updates.wholesalePrice ?? 'removed'}`);
      }

      if (priceInfo.length === 0) {
        return { success: false, message: 'Koi price field nahi diya — sellPrice, costPrice, ya wholesalePrice chahiye' };
      }

      for (const chunk of chunkArray(targets, 500)) {
        const batch = db.batch();
        chunk.forEach(d => batch.update(d.ref, updates));
        await batch.commit();
      }

      return {
        success: true,
        message: `✅ ${targets.length} items ki prices update ho gayi (${priceInfo.join(', ')})`,
      };
    }

    default:
      return { success: false, message: `Unknown action: ${action.action}` };
  }
}

// ── Auth guards ───────────────────────────────────────────────────────────────
// IMPORTANT: checkRevoked:false is intentional for Vercel serverless.
// checkRevoked:true requires an extra Firebase network round-trip that can time
// out on cold starts — causing valid tokens to be rejected with 401.

function _classifyGuardError(errMsg) {
  if (
    errMsg.includes('auth/') ||
    errMsg.includes('Firebase ID token') ||
    errMsg.includes('expired') ||
    errMsg.includes('invalid-argument') ||
    errMsg.includes('INVALID_ARGUMENT')
  ) return 'auth';  // token is bad → 401
  if (
    errMsg.includes('RESOURCE_EXHAUSTED') ||
    errMsg.includes('quota') ||
    errMsg.includes('UNAVAILABLE') ||
    errMsg.includes('8 RESOURCE')
  ) return 'quota'; // Firestore quota/rate → 503
  return 'server';  // infra/unknown → 500
}

async function authGuard(req, res, next) {
  try {
    ensureAdmin();
    const idToken = getBearerToken(req);
    if (!idToken) return res.status(401).json({ error: 'Unauthorized: No token' });
    const decoded = await admin.auth().verifyIdToken(idToken, false);

    // ── Fresh cache hit: skip Firestore read ──
    const cached = _getCached(_authCache, decoded.uid);
    if (cached && cached.fresh) {
      if (!NOTIFICATION_ROLES.has(cached.role)) return res.status(403).json({ error: 'Forbidden' });
      req.authUser = { uid: decoded.uid, role: cached.role };
      return next();
    }

    // ── Cache miss or stale: try Firestore ──
    try {
      const userDoc = await admin.firestore().collection('users').doc(decoded.uid).get();
      const user = userDoc.data() || {};
      if (user.status !== APPROVED_STATUS || !NOTIFICATION_ROLES.has(user.role))
        return res.status(403).json({ error: 'Forbidden' });
      _authCache.set(decoded.uid, { role: user.role, expiresAt: Date.now() + CACHE_TTL_MS });
      req.authUser = { uid: decoded.uid, role: user.role };
      return next();
    } catch (fsErr) {
      const fsMsg = fsErr && fsErr.message ? fsErr.message : String(fsErr);
      // Firestore quota exhausted — fall back to stale cache if available
      if ((fsMsg.includes('RESOURCE_EXHAUSTED') || fsMsg.includes('8 RESOURCE')) && cached) {
        console.warn('[authGuard] Firestore quota hit — using stale cache for', decoded.uid);
        if (!NOTIFICATION_ROLES.has(cached.role)) return res.status(403).json({ error: 'Forbidden' });
        // Extend stale entry so next requests also hit cache
        _authCache.set(decoded.uid, { role: cached.role, expiresAt: Date.now() + CACHE_TTL_MS });
        req.authUser = { uid: decoded.uid, role: cached.role };
        return next();
      }
      // No stale cache — try ADMIN_UIDS env var fallback
      if (fsMsg.includes('RESOURCE_EXHAUSTED') || fsMsg.includes('8 RESOURCE')) {
        if (ADMIN_UIDS_FALLBACK.has(decoded.uid)) {
          console.warn('[authGuard] Firestore quota hit — using ADMIN_UIDS fallback for', decoded.uid);
          _authCache.set(decoded.uid, { role: 'admin', expiresAt: Date.now() + CACHE_TTL_MS });
          req.authUser = { uid: decoded.uid, role: 'admin' };
          return next();
        }
      }
      throw fsErr; // re-throw for other Firestore errors
    }
  } catch (err) {
    const errMsg = err && err.message ? err.message : String(err);
    console.error('[authGuard] Error:', errMsg);
    const kind = _classifyGuardError(errMsg);
    if (kind === 'auth')  return res.status(401).json({ error: 'Unauthorized: Token invalid or expired' });
    if (kind === 'quota') return res.status(503).json({ error: 'Server busy — please retry in 30 seconds', retryAfter: 30 });
    return res.status(500).json({ error: 'Auth server error — please retry', detail: errMsg.slice(0, 200) });
  }
}

async function adminOnlyGuard(req, res, next) {
  try {
    ensureAdmin();
    const idToken = getBearerToken(req);
    if (!idToken) return res.status(401).json({ error: 'Unauthorized: No token' });
    const decoded = await admin.auth().verifyIdToken(idToken, false);

    // ── Fresh cache hit: skip Firestore read ──
    const cached = _getCached(_adminCache, decoded.uid);
    if (cached && cached.fresh) {
      if (!cached.isAdmin) return res.status(403).json({ error: 'Forbidden: Admin only' });
      req.authUser = { uid: decoded.uid, role: 'admin' };
      return next();
    }

    // ── Cache miss or stale: try Firestore ──
    try {
      const userDoc = await admin.firestore().collection('users').doc(decoded.uid).get();
      const user = userDoc.data() || {};
      const isAdmin = user.status === APPROVED_STATUS && user.role === 'admin';
      _adminCache.set(decoded.uid, { isAdmin, expiresAt: Date.now() + CACHE_TTL_MS });
      if (!isAdmin) return res.status(403).json({ error: 'Forbidden: Admin only' });
      req.authUser = { uid: decoded.uid, role: 'admin' };
      return next();
    } catch (fsErr) {
      const fsMsg = fsErr && fsErr.message ? fsErr.message : String(fsErr);
      // Firestore quota exhausted — fall back to stale cache if available
      if ((fsMsg.includes('RESOURCE_EXHAUSTED') || fsMsg.includes('8 RESOURCE')) && cached) {
        console.warn('[adminOnlyGuard] Firestore quota hit — using stale cache for', decoded.uid);
        if (!cached.isAdmin) return res.status(403).json({ error: 'Forbidden: Admin only' });
        // Extend stale entry so next requests also hit cache
        _adminCache.set(decoded.uid, { isAdmin: cached.isAdmin, expiresAt: Date.now() + CACHE_TTL_MS });
        req.authUser = { uid: decoded.uid, role: 'admin' };
        return next();
      }
      // No stale cache — try ADMIN_UIDS env var fallback
      if (fsMsg.includes('RESOURCE_EXHAUSTED') || fsMsg.includes('8 RESOURCE')) {
        if (ADMIN_UIDS_FALLBACK.has(decoded.uid)) {
          console.warn('[adminOnlyGuard] Firestore quota hit — using ADMIN_UIDS fallback for', decoded.uid);
          _adminCache.set(decoded.uid, { isAdmin: true, expiresAt: Date.now() + CACHE_TTL_MS });
          req.authUser = { uid: decoded.uid, role: 'admin' };
          return next();
        }
      }
      throw fsErr; // re-throw for other Firestore errors
    }
  } catch (err) {
    const errMsg = err && err.message ? err.message : String(err);
    console.error('[adminOnlyGuard] Error:', errMsg);
    const kind = _classifyGuardError(errMsg);
    if (kind === 'auth')  return res.status(401).json({ error: 'Unauthorized: Token invalid or expired' });
    if (kind === 'quota') return res.status(503).json({ error: 'Server busy — please retry in 30 seconds', retryAfter: 30 });
    return res.status(500).json({ error: 'Auth server error — please retry', detail: errMsg.slice(0, 200) });
  }
}

async function getRecipientTokens(excludeUid) {
  const snap = await admin.firestore().collection('users').where('status', '==', APPROVED_STATUS).get();
  const seen = new Set();
  const tokens = [];
  snap.forEach((doc) => {
    const user = doc.data() || {};
    const token = typeof user.fcmToken === 'string' ? user.fcmToken.trim() : '';
    if (!token || doc.id === excludeUid || user.role === VIEWER_ROLE || seen.has(token)) return;
    seen.add(token); tokens.push(token);
  });
  return tokens;
}

async function sendDataNotification({ data, excludeUid }) {
  const tokens = await getRecipientTokens(excludeUid);
  if (tokens.length === 0) return { recipients: 0, sent: 0, failed: 0 };
  let sent = 0, failed = 0;
  for (const tokenChunk of chunkArray(tokens, MAX_MULTICAST_TOKENS)) {
    const response = await admin.messaging().sendEachForMulticast({
      tokens: tokenChunk, data,
      android: { priority: 'high', ttl: 60 * 1000 },
    });
    sent += response.successCount; failed += response.failureCount;
  }
  return { recipients: tokens.length, sent, failed };
}

// ── Health ────────────────────────────────────────────────────────────────────
app.get('/', (_req, res) => res.json({ status: 'ok', service: 'Rafay Store API' }));
app.get('/api/health', (_req, res) => res.json({ status: 'ok' }));

// ── Direct WhatsApp Send (for retry — bypasses AI) ───────────────────────────
app.post('/api/whatsapp/send', authGuard, async (req, res) => {
  const WABEES_API_KEY = process.env.WABEES_API_KEY;
  if (!WABEES_API_KEY) {
    return res.json({ type: 'whatsapp', success: false, message: '❌ WABEES_API_KEY configure nahi hai' });
  }
  let { phone, message } = req.body;
  if (!phone || !message) return res.status(400).json({ error: 'phone and message required' });

  let number = String(phone).replace(/[^\d]/g, '');
  if (number.startsWith('0') && number.length === 11) number = '92' + number.slice(1);
  else if (number.startsWith('3') && number.length === 10) number = '92' + number;
  else if (!number.startsWith('92') && number.length === 10) number = '92' + number;

  if (number.length < 11) {
    return res.json({ type: 'whatsapp', success: false, message: `❌ Number galat: ${number}` });
  }

  const whatsappMessage = markdownToWhatsApp(String(message));
  try {
    const waPayload = JSON.stringify({ phone: number, message: whatsappMessage });
    const waResult = await new Promise((resolve) => {
      const waOptions = {
        hostname: 'api.wabees.live',
        path: '/api/send.php',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': WABEES_API_KEY,
          'Content-Length': Buffer.byteLength(waPayload),
        },
      };
      let data = '';
      const waReq = https.request(waOptions, (waRes) => {
        waRes.on('data', chunk => { data += chunk; });
        waRes.on('end', () => {
          try { resolve({ status: waRes.statusCode, body: JSON.parse(data) }); }
          catch { resolve({ status: waRes.statusCode, body: { raw: data.slice(0, 300) } }); }
        });
      });
      waReq.on('error', (e) => resolve({ status: 0, body: { error: e.message } }));
      waReq.setTimeout(20000, () => { waReq.destroy(); resolve({ status: 0, body: { error: 'Timeout' } }); });
      waReq.write(waPayload);
      waReq.end();
    });

    const body = waResult.body;
    const httpOk = waResult.status >= 200 && waResult.status < 300;
    const bodyFailed = (body?.success === false || body?.status === 'error' || body?.status === false ||
      body?.status === 0 || body?.code === 0 || body?.code === false ||
      (typeof body?.error === 'string' && body.error.trim().length > 0 && body.error !== 'null') ||
      (typeof body?.message === 'string' && /fail|error|invalid|not\s+found|expired|banned|blocked/i.test(body.message)));
    const success = httpOk && !bodyFailed;
    const errDetail = body?.error || body?.message || body?.detail || `HTTP ${waResult.status}`;
    const msg = success ? `✅ WhatsApp bhej diya → ${number}` : `❌ Nahi gaya: ${errDetail}`;
    console.log(`[Direct WA] status:${waResult.status} number:${number} body:${JSON.stringify(body).slice(0, 200)}`);
    res.json({ type: 'whatsapp', success, number, message: msg });
  } catch (err) {
    res.json({ type: 'whatsapp', success: false, message: `❌ Error: ${err.message}` });
  }
});

// ── Debug: verify Firebase data counts (admin only) ───────────────────────────
app.get('/api/debug/data', adminOnlyGuard, async (req, res) => {
  try {
    ensureAdmin();
    const db = admin.firestore();
    const [demandSnap, supplierSnap, udhaarSnap, customerSnap, categorySnap] = await Promise.all([
      db.collection('demandItems').get(),
      db.collection('suppliers').get(),
      db.collection('udhaarEntries').get(),
      db.collection('customers').get(),
      db.collection('categories').get(),
    ]);
    const statusCounts = {};
    demandSnap.forEach(doc => {
      const s = (doc.data().status || 'unknown').toLowerCase();
      statusCounts[s] = (statusCounts[s] || 0) + 1;
    });
    res.json({
      demandItems: demandSnap.size,
      demandByStatus: statusCounts,
      suppliers: supplierSnap.size,
      udhaarEntries: udhaarSnap.size,
      customers: customerSnap.size,
      categories: categorySnap.size,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Notifications ─────────────────────────────────────────────────────────────
app.post('/api/notify/demand', authGuard, async (req, res) => {
  try {
    const itemName = cleanString(req.body.itemName);
    const statusChange = cleanString(req.body.statusChange, 40);
    const itemCount = positiveInt(req.body.itemCount);
    if (!itemName) return res.status(400).json({ error: 'itemName required' });
    let title, body;
    if (statusChange) {
      const label = statusChange === 'available' ? 'Available' : statusChange === 'deferred' ? 'Deferred' : statusChange === 'urgent' ? 'Urgent 🚨' : 'Pending';
      title = statusChange === 'urgent' ? '🚨 Urgent Item!' : 'Status Updated';
      body = `"${itemName}" marked as ${label}.`;
    } else if (itemCount > 1) {
      title = '📦 New Demand Items Added'; body = `${itemCount} new items have been added to the demand list.`;
    } else {
      title = '📦 New Demand Item Added'; body = `"${itemName}" has been added to the demand list.`;
    }
    const result = await sendDataNotification({ excludeUid: req.authUser.uid, data: { title, body, type: 'demand' } });
    res.json({ success: true, ...result });
  } catch (err) { console.error('Demand notification failed:', err); res.status(500).json({ error: 'Notification failed' }); }
});

app.post('/api/notify/udhaar', authGuard, async (req, res) => {
  try {
    const title = cleanString(req.body.title);
    const body = cleanString(req.body.body, 240);
    const action = cleanString(req.body.action, 40);
    if (!title || !body) return res.status(400).json({ error: 'title and body required' });
    const result = await sendDataNotification({
      excludeUid: req.authUser.uid,
      data: { title, body, type: 'udhaar', ...(action ? { action } : {}) },
    });
    res.json({ success: true, ...result });
  } catch (err) { console.error('Udhaar notification failed:', err); res.status(500).json({ error: 'Notification failed' }); }
});

// ── AI Chat (Admin only) ──────────────────────────────────────────────────────
app.post('/api/ai/chat', adminOnlyGuard, async (req, res) => {
  const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY;
  const WABEES_API_KEY   = process.env.WABEES_API_KEY;
  if (!DEEPSEEK_API_KEY) return res.status(500).json({ error: 'DEEPSEEK_API_KEY not configured' });

  const messages = req.body.messages;
  const phoneContacts = req.body.phoneContacts || [];
  if (!Array.isArray(messages) || messages.length === 0)
    return res.status(400).json({ error: 'messages array required' });

  const { isNext, offset: pageOffset } = detectPagination(messages);

  // ── Fetch ALL store data from Firestore ────────────────────────────────────
  let firestoreContext = '';
  let allDemands = [], allSuppliers = [], allCustomers = [], allUdhaar = [];
  let dataFetchError = null;

  try {
    ensureAdmin();
    const db = admin.firestore();

    const [demandSnap, supplierSnap, udhaarSnap, customerSnap, categorySnap] = await Promise.all([
      db.collection('demandItems').get(),
      db.collection('suppliers').get(),
      db.collection('udhaarEntries').get(),
      db.collection('customers').get(),
      db.collection('categories').get(),
    ]);

    const catMap = { general: 'General' };
    categorySnap.forEach(doc => { const n = (doc.data().name || '').trim(); if (n) catMap[doc.id] = n; });

    demandSnap.forEach((doc) => {
      const d = doc.data();
      const cid = (d.categoryId || '').trim();
      allDemands.push({
        id: doc.id,
        name: (d.name || d.itemName || '').trim(),
        status: (d.status || 'pending').trim().toLowerCase(),
        qty: d.quantity ? `${d.quantity} ${d.unit || ''}`.trim() : '',
        packContents: (d.packContents || '').trim(),
        notes: (d.notes || '').trim(),
        categoryId: cid,
        catName: catMap[cid || 'general'] || 'General',
        sellPrice: Number(d.sellPrice) || 200.0,
        costPrice: d.costPrice != null ? Number(d.costPrice) : null,
        wholesalePrice: d.wholesalePrice != null ? Number(d.wholesalePrice) : null,
        stock: Number(d.stock) || 500,
      });
    });

    const pending   = allDemands.filter(d => d.status === 'pending');
    const urgent    = allDemands.filter(d => d.status === 'urgent');
    const available = allDemands.filter(d => d.status === 'available');
    const deferred  = allDemands.filter(d => d.status === 'deferred');

    supplierSnap.forEach((doc) => {
      const d = doc.data();
      allSuppliers.push({
        id: doc.id,
        name: (d.name || '').trim(),
        whatsapp: (d.whatsappNumber || d.phone || '').trim(),
        phone: (d.phoneNumber || d.phone || '').trim(),
        products: (d.productsSupplied || '').trim(),
        company: (d.company || '').trim(),
      });
    });

    customerSnap.forEach((doc) => {
      const d = doc.data();
      allCustomers.push({
        id: doc.id,
        name: (d.name || '').trim(),
        phone: (d.phone || d.whatsappNumber || '').trim(),
        whatsapp: (d.whatsappNumber || '').trim(),
        address: (d.address || '').trim(),
      });
    });

    const catItemCounts = {};
    allDemands.forEach(item => {
      const cid = item.categoryId || 'general';
      catItemCounts[cid] = (catItemCounts[cid] || 0) + 1;
    });
    const allCategories = [{ id: 'general', name: 'General (default)', count: catItemCounts['general'] || 0 }];
    categorySnap.forEach((doc) => {
      const d = doc.data();
      allCategories.push({ id: doc.id, name: (d.name || '').trim(), count: catItemCounts[doc.id] || 0 });
    });

    udhaarSnap.forEach((doc) => {
      const d = doc.data();
      allUdhaar.push({
        id: doc.id,
        personName: (d.personName || '').trim(),
        amount: Number(d.amount) || 0,
        type: (d.type || 'given').trim().toLowerCase(),
        status: (d.status || 'pending').trim().toLowerCase(),
        notes: (d.notes || '').trim(),
      });
    });

    const udhaarPending  = allUdhaar.filter(e => e.status === 'pending');
    const udhaarSettled  = allUdhaar.filter(e => e.status === 'settled');
    const udhaarGiven    = udhaarPending.filter(e => e.type === 'given');
    const udhaarReceived = udhaarPending.filter(e => e.type === 'received');
    const totalGiven     = udhaarGiven.reduce((s, e) => s + e.amount, 0);
    const totalReceived  = udhaarReceived.reduce((s, e) => s + e.amount, 0);
    const netBalance     = totalGiven - totalReceived;

    // ── Pricing analytics ──────────────────────────────────────────────────
    const pendingUrgent = [...allDemands.filter(d => d.status === 'pending'), ...allDemands.filter(d => d.status === 'urgent')];
    const puSellTotal = pendingUrgent.reduce((s, d) => s + d.sellPrice, 0);
    const puCostItems = pendingUrgent.filter(d => d.costPrice !== null);
    const puCostTotal = puCostItems.length > 0 ? puCostItems.reduce((s, d) => s + (d.costPrice || 0), 0) : null;
    const puWsItems = pendingUrgent.filter(d => d.wholesalePrice !== null);
    const puWsTotal = puWsItems.length > 0 ? puWsItems.reduce((s, d) => s + (d.wholesalePrice || 0), 0) : null;

    const latestUserMsg = (messages[messages.length - 1]?.content || '').toLowerCase();
    const demandFmt = d =>
      `${d.name}` +
      (d.catName && d.catName !== 'General' ? ` [${d.catName}]` : '') +
      (d.qty ? ` (${d.qty}${d.packContents ? ' × ' + d.packContents : ''})` : '') +
      ` | Sell: Rs ${d.sellPrice}` +
      (d.costPrice !== null ? ` | Cost: Rs ${d.costPrice}` : '') +
      (d.wholesalePrice !== null ? ` | Wholesale: Rs ${d.wholesalePrice}` : '') +
      (d.notes ? ` | ${d.notes.slice(0, 40)}` : '');

    const categoryFilterMatch = allCategories.find(c =>
      c.name !== 'General (default)' && latestUserMsg.includes(c.name.toLowerCase())
    ) || null;

    // Determine which list to page — only filter by status when user EXPLICITLY asks for that status
    // "pending" as a standalone word in context (not as part of another word) triggers status filter
    let demandsToPage = allDemands;
    if (categoryFilterMatch && !isNext) {
      demandsToPage = allDemands.filter(d => (d.categoryId || 'general') === categoryFilterMatch.id);
    } else if (isNext) {
      // Pagination: demandsToPage was already set from prior message — use pending as default
      demandsToPage = pending;
    } else if (/\bsirf pending\b|\bpending items?\b|\bpending list\b|\bpending wale\b/.test(latestUserMsg)) {
      demandsToPage = pending;
    } else if (/\burgent\b/.test(latestUserMsg)) {
      demandsToPage = urgent;
    } else if (/\bavailable\b/.test(latestUserMsg)) {
      demandsToPage = available;
    } else if (/\bdeferred\b/.test(latestUserMsg)) {
      demandsToPage = deferred;
    }

    const pagedDemand = buildPagedList(isNext ? demandsToPage : pending, isNext ? pageOffset : 0, 'name', demandFmt);
    const pagedUrgent = buildPagedList(urgent, 0, 'name', demandFmt);

    const supplierPage = allSuppliers.slice(0, PAGE_SIZE);
    const supplierRemaining = allSuppliers.length - supplierPage.length;
    const customerPage = allCustomers.slice(0, 50);
    const customerRemaining = allCustomers.length - customerPage.length;

    firestoreContext = `
=== RAFAY STORE — LIVE FIREBASE DATA (fetched right now) ===

━━━ DEMAND ITEMS SUMMARY ━━━
TOTAL demand items : ${allDemands.length}
  • Pending   : ${pending.length}
  • Urgent    : ${urgent.length}
  • Available : ${available.length}
  • Deferred  : ${deferred.length}

Pending items (showing ${Math.min(PAGE_SIZE, pending.length)} of ${pending.length}):
${pagedDemand.text}

Urgent items (${urgent.length} total):
${pagedUrgent.text}

Available items list:
${buildPagedList(available, 0, 'name', demandFmt).text}

Deferred items list:
${buildPagedList(deferred, 0, 'name', demandFmt).text}

━━━ SUPPLIERS (${allSuppliers.length} total) ━━━
${supplierPage.map(s =>
  `  • ${s.name}${s.company ? ' (' + s.company + ')' : ''}${s.products ? ' [' + s.products + ']' : ''} | WhatsApp: ${s.whatsapp || 'N/A'} | Phone: ${s.phone || 'N/A'}`
).join('\n') || '  (none)'}${supplierRemaining > 0 ? `\n  ... (${supplierRemaining} more — ask to see more)` : ''}

━━━ CUSTOMERS (${allCustomers.length} total) ━━━
${customerPage.map(c =>
  `  • ${c.name} | WhatsApp: ${c.whatsapp || 'N/A'} | Phone: ${c.phone || 'N/A'}${c.address ? ' | ' + c.address : ''}`
).join('\n') || '  (none)'}${customerRemaining > 0 ? `\n  ... (${customerRemaining} more — ask to see more)` : ''}

━━━ CATEGORIES (${allCategories.length} total) ━━━
${allCategories.map(c => '  • ' + c.name + ' (' + c.count + ' items) — id: ' + c.id).join('\n')}

━━━ UDHAAR KHATA ━━━
TOTAL udhaar entries : ${allUdhaar.length}
  • Pending (unsettled) : ${udhaarPending.length}
  • Settled             : ${udhaarSettled.length}

Pending breakdown:
  • Dena hai  (given) : ${udhaarGiven.length} entries — Rs ${totalGiven.toFixed(0)}
  • Lena hai  (recv)  : ${udhaarReceived.length} entries — Rs ${totalReceived.toFixed(0)}
  • Net balance       : Rs ${netBalance.toFixed(0)} ${netBalance >= 0 ? '(logon ne dena hai)' : '(hamne dena hai)'}

Pending udhaar details:
${udhaarPending.map(e =>
  `  • ${e.personName} — Rs ${e.amount} (${e.type === 'given' ? 'dena hai' : 'lena hai'})${e.notes ? ' — ' + e.notes : ''}`
).join('\n') || '  (none)'}

━━━ PRICING SUMMARY — PENDING + URGENT ITEMS ━━━
Total pending+urgent items : ${pendingUrgent.length}
  • Total Sell Price   : Rs ${puSellTotal.toFixed(0)} (all ${pendingUrgent.length} items)
  • Total Cost Price   : ${puCostTotal !== null ? `Rs ${puCostTotal.toFixed(0)} (${puCostItems.length} items have cost price set)` : '(no cost prices set)'}
  • Total Wholesale    : ${puWsTotal !== null ? `Rs ${puWsTotal.toFixed(0)} (${puWsItems.length} items have wholesale price set)` : '(no wholesale prices set)'}
${puCostTotal !== null ? `  • Profit Margin (Sell-Cost) : Rs ${(puSellTotal - puCostTotal).toFixed(0)} (${puSellTotal > 0 ? ((puSellTotal - puCostTotal) / puSellTotal * 100).toFixed(1) : 0}%)` : ''}

━━━ SMART REORDER ALERTS ━━━
${(() => {
  const urgentItems = urgent.slice(0, 20);
  if (urgentItems.length === 0) return '  (No urgent items currently)';
  return urgentItems.map(item => {
    const itemWords = item.name.toLowerCase().split(/\s+/);
    const matched = allSuppliers.find(s =>
      s.products && itemWords.some(w => w.length > 2 && s.products.toLowerCase().includes(w))
    );
    const supplierPart = matched
      ? ` → ${matched.name} (${matched.whatsapp || matched.phone || 'no number'})`
      : ' → (no supplier linked)';
    return `  ⚠ ${item.name}${item.qty ? ' (' + item.qty + ')' : ''} | Sell: Rs ${item.sellPrice}${item.costPrice !== null ? ` | Cost: Rs ${item.costPrice}` : ''}${supplierPart}`;
  }).join('\n');
})()}
=== END OF STORE DATA ===`;

  } catch (err) {
    dataFetchError = err.message;
    firestoreContext = `(Store data could not be loaded — ${err.message})`;
    console.error('[AI] Firestore fetch error:', err);
  }

  let contactsContext = '';
  if (phoneContacts.length > 0) {
    contactsContext = `\n\n━━━ USER'S PHONE CONTACTS (${phoneContacts.length} total — for WhatsApp messages) ━━━\n` +
      phoneContacts.slice(0, 200).map(c => `  • ${c.name} | ${c.phone}`).join('\n');
    if (phoneContacts.length > 200) contactsContext += `\n  ... (${phoneContacts.length - 200} more)`;
  }

  // ── System Prompt ──────────────────────────────────────────────────────────
  const systemPrompt = `You are the AI assistant for Rafay Store (Pakistan grocery/kirana store). You have FULL CONTROL over the store database — read, add, update, delete everything, and send WhatsApp messages.

${firestoreContext}${contactsContext}
${dataFetchError ? `\nWARNING: Could not load store data (${dataFetchError}). Inform admin.` : ''}

━━━ CRITICAL RULES ━━━
1. COUNTS: Use ONLY the exact COUNT numbers shown above. NEVER count names in a list — they may be truncated.
2. LANGUAGE: Reply in same language as user (Urdu, Roman Urdu, or English). Support all three fluently.
3. TODAY: ${new Date().toLocaleDateString('en-PK', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}
4. PAKISTAN NUMBERS: Always convert 03XXXXXXXXX → 923XXXXXXXXX for WhatsApp.
5. PAGINATION: Items shown in batches of 100. When user says "next"/"more"/"agle", show next batch.
6. FORMATTING: Use rich markdown — **bold**, _italic_, # Heading, ## Sub-heading, - bullet list, > blockquote. For comparisons/data use markdown tables.
7. CONTACTS: When user wants to message someone by name, first check phone contacts, then suppliers, then customers.
8. ITEM vs WHATSAPP: "karo" alone means "do/perform" — NOT WhatsApp. Distinguish carefully:
    ITEM SEARCH: "chawal search karo", "check karo", "hai kya", "available hai", "status batao" → use search_demand_items action
    WHATSAPP: "Ali ko WhatsApp karo", "message bhejo", "Ali ko msg karo" → only when BOTH a name AND explicit send/message/whatsapp word exist
    If no explicit WhatsApp keyword (whatsapp/message/msg/send/bhejo), ALWAYS treat as item/data query.
    IMPORTANT: For ANY item search — "X search karo", "X hai kya", "X check karo" — ALWAYS use {"action":"search_demand_items","query":"X"} even if X appears in context above. This ensures accurate results from ALL items.
9. WHATSAPP MANDATORY: EVERY WhatsApp send request — even repeated ones — MUST include a fresh send_whatsapp action JSON. History does NOT count. Always generate JSON.
10. TABLES: Use markdown table syntax for any structured/comparative data.
11. SMART REPLIES: Anticipate follow-up questions. After showing a list, hint what user can do next.
12. HONEST REPORTING — CRITICAL:
    ✦ NEVER say "ho gaya", "add ho gaya", "delete ho gaya" BEFORE the action executes.
    ✦ Your text reply is shown WHILE the action runs. Say what you ARE DOING, not what you DID.
    ✦ CORRECT: "Theek hai, main ab add kar raha hoon..." or "Yeh action chal raha hai..."
    ✦ WRONG: "Add ho gaya ✅" — you cannot know this before the server confirms.
    ✦ The server will append the real ✅/❌ result automatically after your reply.
    ✦ If user says "add karo", say "Ab add kar raha hoon" — NOT "Add ho gaya".

━━━ ADVANCED INTELLIGENCE RULES ━━━
• URDU/ROMAN URDU: Fully understand and reply in Urdu script AND Roman Urdu. Switch naturally.
• CONTEXT MEMORY: Remember earlier messages in this conversation for continuity.
• CALCULATIONS: Do math on udhaar amounts, totals, averages. Show working if complex.
• SMART SEARCH: If user asks for an item/person with a typo, find the closest match and confirm.
• DATA ANALYSIS: Spot trends (most urgent items, highest udhaar, busiest suppliers).
• PROACTIVE: Warn about urgent items, high udhaar, missing info. Suggest actions.
• CONFIRMATION: For deletes and settlements, summarise what will change before doing it.
• SAFE DELETES: Never delete without confirming. State exactly what will be deleted.

━━━ YOUR FULL CAPABILITIES ━━━
✅ View all data (demand, suppliers, customers, udhaar) — paginated 100 at a time
✅ Search demand items by name (partial match) — use search_demand_items action
✅ Add / update / delete demand items (single or bulk) — with packContents support
✅ Change demand item status (pending/available/deferred/urgent) — single or bulk
✅ Add / update / delete suppliers
✅ Add / update / delete customers
✅ Add udhaar entries, settle udhaar, delete udhaar, update udhaar amount/notes
✅ Add / update / delete categories
✅ Assign category to a single item OR to ALL items matching a filter (bulk)
✅ Filter and list demand items by category
✅ Send WhatsApp to ANY number or by name (check contacts, suppliers, customers)
✅ Bulk add many items at once (up to 500 per request)
✅ Bulk assign a category to 200+ items in one shot
✅ Bulk delete items by name, category, or status (with safety confirmation)
✅ Analyse and summarise all store data
✅ Search items by price range (sell/cost/wholesale)
✅ Bulk update prices (sell/cost/wholesale) for matching items
✅ Calculate profit margins and pricing reports from live data

━━━ BULK OPERATIONS — HOW TO USE ━━━

► BULK ASSIGN CATEGORY (e.g. "Ration category mein yeh 200 items assign karo"):
  Use bulk_assign_category with an optional nameFilter OR without filter for ALL items.
  {"actions":[
    {"action":"bulk_assign_category","categoryId":"<category_id>","nameFilter":"rice"}
  ]}
  Without nameFilter → assigns to ALL demand items.
  With nameFilter → assigns to items whose name contains that text.

► BULK ADD ITEMS (e.g. "yeh 5 items add karo demand list mein"):
  {"actions":[
    {"action":"bulk_add_demand_items","items":[
      {"name":"Chawal","quantity":"10","unit":"Kg","status":"pending","categoryId":"<id>"},
      {"name":"Daal","quantity":"5","unit":"Kg","status":"pending"},
      {"name":"Atta","quantity":"20","unit":"Kg","status":"pending"}
    ]}
  ]}

► BULK DELETE ITEMS (e.g. "Ration category ke saare items delete karo"):
  {"actions":[{"action":"bulk_delete_demand_items","categoryId":"<category_id>"}]}
  OR by name filter:
  {"actions":[{"action":"bulk_delete_demand_items","nameFilter":"rice"}]}
  OR by status:
  {"actions":[{"action":"bulk_delete_demand_items","status":"deferred"}]}
  SAFETY: Blank filter not allowed — at least nameFilter, categoryId, or status must be provided.
  CONFIRM with user before bulk deleting — tell them how many items will be deleted first.

► BULK UPDATE STATUS (e.g. "Ration category ke saare items available kar do"):
  {"actions":[
    {"action":"bulk_update_status","status":"available","categoryName":"Ration"}
  ]}
  OR by exact Firestore ID:
  {"actions":[
    {"action":"bulk_update_status","status":"available","categoryId":"<category_id>"}
  ]}
  OR by name pattern:
  {"actions":[
    {"action":"bulk_update_status","status":"available","nameFilter":"rice"}
  ]}

► MULTIPLE SEQUENTIAL ACTIONS (e.g. "category add karo phir items bhi add karo"):
  {"actions":[
    {"action":"add_category","name":"Ration"},
    {"action":"add_demand_item","name":"Chawal","categoryId":"<new_id>"}
  ]}
  NOTE: For sequential actions where later actions depend on earlier ones (e.g. need the new category ID),
  do them in separate messages. For independent actions, use the actions array.
  PREFERRED FOR CATEGORY ASSIGN: Use bulk_assign_category_by_name — it resolves category name automatically.
  Example: User says "Ration category create karo phir chawal items assign karo"
  Step 1 (first message): {"actions":[{"action":"add_category","name":"Ration"}]}
  Step 2 (next message when user says assign): {"actions":[{"action":"bulk_assign_category_by_name","categoryName":"Ration","nameFilter":"chawal"}]}

━━━ SINGLE ACTION JSON FORMAT ━━━
Put ONE JSON block OR one {"actions":[...]} block at the VERY END of your reply, after all text.

SEND WHATSAPP:
{"action":"send_whatsapp","number":"923001234567","message":"WhatsApp message text"}

SEARCH DEMAND ITEMS — Use this whenever user asks to find/search a specific item by name (partial match supported):
{"action":"search_demand_items","query":"naswar"}
{"action":"search_demand_items","query":"chawal","status":"available"}
IMPORTANT: For item searches ("X search karo", "X hai kya", "X available hai"), ALWAYS use search_demand_items action — it searches ALL items regardless of pagination limits.

ADD DEMAND ITEM (with optional category — use categoryName, NOT categoryId):
{"action":"add_demand_item","name":"Item Name","quantity":"10","unit":"Carton","packContents":"10 kg","notes":"","status":"pending","categoryName":"Ration"}
(categoryName: use the category name directly, e.g. "Ration", "Grocery". Use "general" or omit to leave uncategorized)
(packContents = what's inside each pack, e.g. "10 kg", "500 ml", "12 pcs" — optional but very useful for WhatsApp ordering)

UPDATE DEMAND ITEM (name/qty/unit/notes/status/categoryName):
{"action":"update_demand_item","name":"Old Name","newName":"New Name","quantity":"5","status":"available","categoryName":"Ration"}
(use categoryName:"general" to remove category / reset to General)

CHANGE DEMAND STATUS ONLY:
{"action":"update_demand_status","name":"Item Name","status":"available"}
(status: pending / available / deferred / urgent)

DELETE DEMAND ITEM:
{"action":"delete_demand_item","name":"Item Name"}

ADD SUPPLIER:
{"action":"add_supplier","name":"Name","company":"","productsSupplied":"Rice Sugar","whatsappNumber":"923001234567","phoneNumber":""}

UPDATE SUPPLIER:
{"action":"update_supplier","name":"Name","newName":"New Name","whatsappNumber":"923001234567"}

DELETE SUPPLIER:
{"action":"delete_supplier","name":"Supplier Name"}

ADD CUSTOMER:
{"action":"add_customer","name":"Name","phone":"923001234567","whatsappNumber":"923001234567","address":"Lahore","notes":""}

UPDATE CUSTOMER:
{"action":"update_customer","name":"Name","phone":"923001234567","address":"New Address"}

DELETE CUSTOMER:
{"action":"delete_customer","name":"Customer Name"}

ADD UDHAAR:
{"action":"add_udhaar","personName":"Name","amount":5000,"type":"given","notes":""}
(type: "given"=dena hai / "received"=lena hai)

SETTLE UDHAAR:
{"action":"settle_udhaar","name":"Person Name"}

DELETE UDHAAR:
{"action":"delete_udhaar","name":"Person Name"}

UPDATE UDHAAR (amount/type/notes — only pending):
{"action":"update_udhaar","name":"Person Name","amount":8000,"type":"given","notes":"Updated note"}

ADD CATEGORY:
{"action":"add_category","name":"Category Name"}

UPDATE CATEGORY (use exact id from categories list, OR use name if id unknown):
{"action":"update_category","id":"firestore_doc_id","newName":"New Name"}
{"action":"update_category","name":"Old Name","newName":"New Name"}

DELETE CATEGORY (use exact id from categories list, OR use name):
{"action":"delete_category","id":"firestore_doc_id"}
{"action":"delete_category","name":"Category Name"}

ASSIGN CATEGORY TO ONE ITEM (PREFERRED — use categoryName, no ID needed):
{"action":"update_demand_item","name":"Item Name","categoryName":"Ration"}
{"action":"update_demand_item","name":"Item Name","categoryName":"General"}
(use categoryName:"general" to reset to General — OR use categoryId:"category_id" if you have exact ID)

BULK ASSIGN CATEGORY BY NAME (PREFERRED — no ID needed, resolves automatically):
{"actions":[{"action":"bulk_assign_category_by_name","categoryName":"Ration"}]}
{"actions":[{"action":"bulk_assign_category_by_name","categoryName":"Beverages","nameFilter":"juice"}]}
USE THIS instead of bulk_assign_category when you don't have the exact Firestore ID.

BULK ASSIGN CATEGORY (use only if you have exact category ID from the categories list):
{"actions":[{"action":"bulk_assign_category","categoryId":"exact_firestore_id","nameFilter":"rice"}]}

BULK ADD ITEMS:
{"actions":[{"action":"bulk_add_demand_items","items":[{"name":"Item1","quantity":"1","unit":"Piece","status":"pending"},{"name":"Item2"}]}]}

BULK DELETE ITEMS (by name/category/status — CONFIRM with user before sending):
{"actions":[{"action":"bulk_delete_demand_items","nameFilter":"rice"}]}
{"actions":[{"action":"bulk_delete_demand_items","categoryId":"category_id"}]}
{"actions":[{"action":"bulk_delete_demand_items","status":"deferred"}]}

PRICING ANALYTICS REPORT (per-category breakdown):
{"action":"get_pricing_analytics","statusFilter":"all"}
{"action":"get_pricing_analytics","statusFilter":"pending_urgent"}
(statusFilter: all / pending / urgent / pending_urgent / available / deferred)

SEARCH BY PRICE RANGE:
{"action":"search_by_price","priceField":"sellPrice","minPrice":100,"maxPrice":500}
{"action":"search_by_price","priceField":"costPrice","minPrice":0,"maxPrice":300,"status":"pending"}
(priceField: sellPrice / costPrice / wholesalePrice)

BULK UPDATE PRICES (name/category/status filter — ALWAYS get confirmation first):
{"action":"bulk_update_price","nameFilter":"rice","sellPrice":250,"costPrice":200}
{"action":"bulk_update_price","categoryId":"<id>","sellPrice":300,"wholesalePrice":280}
{"action":"bulk_update_price","status":"pending","costPrice":150,"confirmAll":true}
(use confirmAll:true only if user explicitly confirmed updating ALL items)

PRICING REPORT — QUICK (use PRICING SUMMARY section above — no action needed):
For simple total questions (e.g. "total sell of pending items"), use the PRICING SUMMARY above directly.
For per-category breakdown, use get_pricing_analytics action.

━━━ ACTION RULES ━━━
- ONE JSON block per reply (either single action or {"actions":[...]} array)
- Put JSON at VERY END after all text
- NEVER pre-claim success/failure — just say what you are doing
- For ambiguous deletes and bulk price updates: ask for confirmation first, show what will change
- When showing lists: show counts first, then paginated names
- ALWAYS prefer bulk_assign_category_by_name over bulk_assign_category — it uses category name not ID
- For pricing reports: use the PRICING SUMMARY section — no action needed, just calculate and reply

━━━ MULTI-TURN CONVERSATION RULES — CRITICAL ━━━
When user gives a FOLLOW-UP command in the same chat (after a first command succeeded):
1. ALWAYS re-read the latest CATEGORIES list in the store data above — it is fetched fresh each request.
2. ALWAYS use bulk_assign_category_by_name with the category NAME (not ID) for category assignments.
3. If user says "in categories ke mutabiq products assign karo" or similar, generate MULTIPLE actions:
   {"actions":[
     {"action":"bulk_assign_category_by_name","categoryName":"Ration","nameFilter":"chawal"},
     {"action":"bulk_assign_category_by_name","categoryName":"Ration","nameFilter":"daal"},
     {"action":"bulk_assign_category_by_name","categoryName":"Beverages","nameFilter":"juice"}
   ]}
4. NEVER say "ho gaya" before the action result comes back from server.
5. If the previous assistant message showed category IDs (e.g. "ID: abc123"), use bulk_assign_category with that exact ID.
6. For ANY follow-up that modifies data: ALWAYS generate the JSON action — never skip it just because the conversation says it was done.

━━━ CONTACT MATCHING RULES ━━━
When user says "X ko WhatsApp karo" — find X in this order:
1. Phone contacts list (priority) — search by name
2. Suppliers list
3. Customers list
If multiple matches found: list them and ask which one.
If no match found: ask for the phone number directly.

IMPORTANT — URDU SCRIPT NAMES FROM VOICE:
Voice input often produces Urdu script names. When a name appears in Urdu script, ALSO try its common Roman Urdu equivalents:
  زین → Zain, Zein | احمد → Ahmad, Ahmed | علی → Ali | رفیع → Rafi, Rafay
  عمر → Umar, Omar | حسن → Hassan, Hasan | محمد → Muhammad, Mohammad

━━━ CATEGORY FILTER INSTRUCTIONS ━━━
When user asks about items in a category:
→ Filter the relevant items by their [Category] tag and list them grouped by status
→ Show summary first: "Ration category mein X items hain: Y pending, Z available, W deferred, V urgent"
→ Then list each item with its status
→ If category not found: say so and list available categories with counts

━━━ SMART REORDER ALERT INSTRUCTIONS ━━━
When asked about reorders / urgent items:
→ Use SMART REORDER ALERTS section above
→ Proactively say: "X urgent items need restocking. Want me to WhatsApp [Supplier]?"

━━━ TERMINOLOGY ━━━
- Pending = items ordered but not yet received
- Available = items in stock
- Urgent = items critically needed (notification sent to all users)
- Dena hai / given = store gave credit (they owe us)
- Lena hai / received = someone gave us credit (we owe them)`;

  // ── Sanitize conversation history ──────────────────────────────────────────
  // For user messages in history (not the last one), strip the injected
  // context blocks (live stats, local item search results, contact info).
  // These were useful for the AI at the time, but re-sending them in every
  // historical turn balloons the context window, causing the AI to lose focus
  // and confabulate after 2-3 turns. The system prompt already has fresh data.
  const sanitizedMessages = messages.map((m, idx) => {
    const isLastMessage = idx === messages.length - 1;
    let content = String(m.content || '');

    if (m.role === 'assistant') {
      // Strip action-result suffixes so AI doesn't pattern-match "done" and skip JSON
      content = content.replace(/\n\n[✅❌🔄][^\n]*/g, '').trim();
    } else if (m.role === 'user' && !isLastMessage) {
      // Strip all injected context blocks from historical user turns.
      // Keep only the raw user text so history stays compact.
      content = content
        .replace(/\n\n\[LIVE STORE STATS[\s\S]*?\]/g, '')
        .replace(/\n\n\[App has \d+ total demand items[\s\S]*?\]/g, '')
        .replace(/\n\n\[Contact found:[^\]]*\]/g, '')
        .replace(/\n\n\[User selected contact:[^\]]*\]/g, '')
        .trim();
    }

    return { role: m.role, content };
  });

  // ── Call DeepSeek API ──────────────────────────────────────────────────────
  let aiReply = '';
  try {
    const payload = JSON.stringify({
      model: 'deepseek-chat',
      messages: [
        { role: 'system', content: systemPrompt },
        ...sanitizedMessages,
      ],
      max_tokens: 3000,
      temperature: 0.1,
    });

    aiReply = await new Promise((resolve, reject) => {
      const options = {
        hostname: 'api.deepseek.com',
        path: '/v1/chat/completions',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${DEEPSEEK_API_KEY}`,
          'Content-Length': Buffer.byteLength(payload),
        },
      };
      let data = '';
      const apiReq = https.request(options, (apiRes) => {
        apiRes.on('data', chunk => { data += chunk; });
        apiRes.on('end', () => {
          try {
            const parsed = JSON.parse(data);
            if (parsed.error) return reject(new Error(parsed.error.message || 'DeepSeek error'));
            resolve(parsed.choices?.[0]?.message?.content || '');
          } catch { reject(new Error('Invalid DeepSeek response: ' + data.slice(0, 200))); }
        });
      });
      apiReq.on('error', reject);
      apiReq.setTimeout(55000, () => { apiReq.destroy(); reject(new Error('DeepSeek timeout')); });
      apiReq.write(payload);
      apiReq.end();
    });
  } catch (err) {
    console.error('[AI] DeepSeek error:', err.message);
    return res.status(502).json({ error: 'AI service error: ' + err.message });
  }

  // ── Extract action(s) from AI reply ───────────────────────────────────────
  const { single: singleAction, bulk: bulkActions } = extractActions(aiReply);
  let cleanReply = stripActionBlocks(aiReply);

  // ── Execute action(s) ──────────────────────────────────────────────────────
  let actionResult = null;
  const db = admin.firestore();

  // Helper: execute one non-WhatsApp Firestore action and append result
  async function runFirestoreAction(actionData) {
    try {
      const result = await executeFirestoreAction(actionData, db);
      if (result) {
        console.log(`[AI][Action] ${actionData.action} — ${result.message}`);
        cleanReply += `\n\n${result.message}`;

        // Push notifications for key events
        if (actionData.action === 'update_demand_status' && result.success && result.statusChange) {
          try {
            const tokens = await getRecipientTokens(req.authUser.uid);
            if (tokens.length > 0) {
              const isUrgent = result.statusChange === 'urgent';
              await admin.messaging().sendEachForMulticast({
                tokens,
                data: {
                  title: isUrgent ? '🚨 Urgent Item!' : '📦 Status Updated',
                  body: `"${actionData.name}" marked as ${result.statusChange}`,
                  type: 'demand',
                },
                android: { priority: 'high', ttl: 60 * 1000 },
              });
            }
          } catch (notifErr) { console.warn('[AI][Notif] Push failed:', notifErr.message); }
        }
        if (actionData.action === 'add_demand_item' && result.success) {
          try {
            const tokens = await getRecipientTokens(req.authUser.uid);
            if (tokens.length > 0) {
              await admin.messaging().sendEachForMulticast({
                tokens,
                data: {
                  title: '📦 New Demand Item',
                  body: `"${actionData.name}" has been added to the demand list.`,
                  type: 'demand',
                },
                android: { priority: 'high', ttl: 60 * 1000 },
              });
            }
          } catch (notifErr) { console.warn('[AI][Notif] Push failed:', notifErr.message); }
        }
        return { type: actionData.action, ...result };
      }
    } catch (err) {
      const errMsg = `❌ Action "${actionData.action}" fail: ${err.message}`;
      console.error(`[AI][Action] ${actionData.action} error:`, err.message);
      cleanReply += `\n\n${errMsg}`;
      return { type: actionData.action, success: false, error: err.message, message: errMsg };
    }
    return null;
  }

  if (bulkActions && bulkActions.length > 0) {
    // Execute multiple actions sequentially and collect all results
    const results = [];
    for (const act of bulkActions) {
      if (!act || typeof act.action !== 'string') continue;
      if (act.action === 'send_whatsapp') {
        // WhatsApp in bulk — skip for now, only support as single action
        cleanReply += '\n\n⚠️ WhatsApp bulk send supported nahi hai — ek ek bhejo.';
        continue;
      }
      const r = await runFirestoreAction(act);
      if (r) results.push(r);
    }
    if (results.length > 0) {
      const successCount = results.filter(r => r.success).length;
      actionResult = {
        type: 'bulk',
        success: successCount === results.length,
        results,
        message: `${successCount}/${results.length} actions successful`,
      };
    }

  } else if (singleAction) {
    if (singleAction.action === 'send_whatsapp') {
      // ── WhatsApp single action ─────────────────────────────────────────────
      let number = String(singleAction.number || '').replace(/[^\d]/g, '');
      const originalMessage = String(singleAction.message || '').trim();

      // replace(/[^\d]/g, '') above already strips '+' and all non-digits,
      // so the old `if (number.startsWith('+'))` check here was dead code.
      if (number.startsWith('0') && number.length === 11) number = '92' + number.slice(1);
      else if (number.startsWith('3') && number.length === 10) number = '92' + number;
      else if (!number.startsWith('92') && number.length === 10) number = '92' + number;

      if (!WABEES_API_KEY) {
        actionResult = { type: 'whatsapp', success: false, message: '❌ WhatsApp API key configure nahi hai — Vercel mein WABEES_API_KEY set karo' };
        cleanReply += `\n\n${actionResult.message}`;
      } else if (number.length < 11) {
        actionResult = { type: 'whatsapp', success: false, message: `❌ Number galat format: "${number}" — Pakistan number 923XXXXXXXXX hona chahiye` };
        cleanReply += `\n\n${actionResult.message}`;
      } else if (!originalMessage) {
        actionResult = { type: 'whatsapp', success: false, message: '❌ Message khali nahi ho sakta' };
        cleanReply += `\n\n${actionResult.message}`;
      } else {
        const whatsappMessage = markdownToWhatsApp(originalMessage);
        try {
          const waPayload = JSON.stringify({ phone: number, message: whatsappMessage });
          const waResult = await new Promise((resolve) => {
            const waOptions = {
              hostname: 'api.wabees.live',
              path: '/api/send.php',
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'X-Api-Key': WABEES_API_KEY,
                'Content-Length': Buffer.byteLength(waPayload),
              },
            };
            let data = '';
            const waReq = https.request(waOptions, (waRes) => {
              waRes.on('data', chunk => { data += chunk; });
              waRes.on('end', () => {
                try { resolve({ status: waRes.statusCode, body: JSON.parse(data) }); }
                catch { resolve({ status: waRes.statusCode, body: { raw: data.slice(0, 300) } }); }
              });
            });
            waReq.on('error', (e) => resolve({ status: 0, body: { error: e.message } }));
            waReq.setTimeout(20000, () => { waReq.destroy(); resolve({ status: 0, body: { error: 'Timeout after 20s' } }); });
            waReq.write(waPayload);
            waReq.end();
          });

          const body = waResult.body;
          const httpOk = waResult.status >= 200 && waResult.status < 300;
          const bodyFailed = (
            body?.success === false || body?.status === 'error' || body?.status === false ||
            body?.status === 0 || body?.code === 0 || body?.code === false ||
            (typeof body?.error === 'string' && body.error.trim().length > 0 && body.error !== 'null') ||
            (typeof body?.message === 'string' && /fail|error|invalid|not\s+found|expired|banned|blocked/i.test(body.message))
          );
          const waSuccess = httpOk && !bodyFailed;
          let errDetail = '';
          if (!waSuccess) {
            if (typeof body === 'object' && body !== null) {
              errDetail = body.error || body.message || body.detail || body.reason ||
                (body.status ? `status: ${body.status}` : '') || JSON.stringify(body).slice(0, 200);
            } else {
              errDetail = String(body || '').slice(0, 200);
            }
            if (!errDetail) errDetail = `HTTP ${waResult.status}`;
          }
          const waStatusMsg = waSuccess
            ? `✅ WhatsApp bhej diya gaya → ${number}`
            : `❌ WhatsApp send nahi hua: ${errDetail}`;

          console.log(`[AI][WhatsApp] status:${waResult.status} number:${number} — ${waStatusMsg}`);
          actionResult = {
            type: 'whatsapp',
            number,
            originalMessage,
            success: waSuccess,
            status: waResult.status,
            response: waResult.body,
            message: waStatusMsg,
          };
          cleanReply += `\n\n${waStatusMsg}`;
        } catch (err) {
          const errMsg = `❌ WhatsApp send fail: ${err.message}`;
          console.error('[AI][WhatsApp] Exception:', err.message);
          actionResult = { type: 'whatsapp', number, success: false, error: err.message, message: errMsg };
          cleanReply += `\n\n${errMsg}`;
        }
      }
    } else {
      // Single Firestore action
      const r = await runFirestoreAction(singleAction);
      if (r) actionResult = r;
    }
  }

  if (isNext && !cleanReply.includes('[OFFSET:')) {
    cleanReply += `\n[OFFSET:${pageOffset}]`;
  }

  return res.json({
    reply: cleanReply || aiReply,
    actionResult: actionResult || null,
  });
});

if (require.main === module) {
  const PORT = process.env.PORT || 3000;
  app.listen(PORT, '0.0.0.0', () => console.log(`Rafay Store API running on port ${PORT}`));
}

module.exports = app;
