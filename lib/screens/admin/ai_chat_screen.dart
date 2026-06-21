import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../../core/theme.dart';
import '../../models/demand_item_model.dart';
import '../../providers/category_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/demand_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../providers/udhaar_provider.dart';
import '../../services/ai_service.dart';
import '../../services/contacts_service.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with TickerProviderStateMixin {
  // Definitive WhatsApp intent — Roman Urdu AND Urdu script both covered.
  // Without Urdu script patterns, voice input in Urdu would never trigger the popup.
  static final _definiteWaRegex = RegExp(
    r'('
    r'\bwhatsapp\b'                        // Roman: whatsapp
    r'|\bwa\s+(bhej|send|karo|do)\b'       // Roman: wa bhej/send/karo/do
    r'|\u0648\u0627\u0679\u0633'           // واٹس  (correct U+0679 ٹ)
    r'|\u0648\u0627\u0479\u0633'           // واٹس  (legacy U+0479 from some TTS engines)
    r'|\u0648\u0627\u062A\u0633'           // واتس  (alternate spelling)
    r'|\u0645\u06CC\u0633\u062C'           // میسج  (message — Urdu script)
    r'|\u0628\u06BE\u06CC\u062C\u0648'    // بھیجو (bhejo/send)
    r'|\u0628\u06BE\u06CC\u062C'          // بھیج  (bhej/send)
    r'|\u0627\u0631\u0633\u0627\u0644'    // ارسال (irsal/send)
    r')',
    caseSensitive: false,
  );

  final _svc = AiService.instance;
  final _contactsSvc = ContactsService.instance;

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // ── Typing indicator animation ─────────────────────────────────────────────
  late AnimationController _typingAnimController;

  // ── Voice input ────────────────────────────────────────────────────────────
  final SpeechToText _speech = SpeechToText();
  late AnimationController _micPulseController;
  late Animation<double> _micPulseAnim;
  bool _speechReady = false;
  bool _isListening = false;
  String _voiceLocale = 'ur_PK';
  double _soundLevel = 0.0;

  // ── State flags ────────────────────────────────────────────────────────────
  bool _isLoading = false;
  bool _contactsLoading = false;
  // Issue 1 fix: prevents the final onResult callback (fired AFTER stop()) from
  // re-populating the text field after the user hits Send while voice is active.
  bool _suppressVoiceResults = false;

  // ── WhatsApp retry state ────────────────────────────────────────────────────
  // Stored whenever the AI triggers a WhatsApp send, so the Retry button can
  // re-send directly without going through the AI again.
  String? _lastWaPhone;
  String? _lastWaMessage;
  bool _lastWaFailed = false;

  static const List<String> _quickPrompts = [
    'Show pending items',
    'Show urgent items',
    'Low stock items',
    'Udhaar summary',
    'Show customers',
    'Show suppliers',
    'Bulk add: Rice, Wheat, Sugar',
    'Delete all deferred items',
    'Show pricing analytics',
    'Next',
  ];

  // Regex to detect WhatsApp/messaging intent.
  // Covers Roman Urdu + Urdu script (both U+0479 and U+0679 for ٹ — different
  // voice-recognition engines/Android versions return different code points).
  // INTENTIONALLY excludes "karo", "call", "contact", "fon" — too generic in Urdu.
  static final _waIntentRegex = RegExp(
    r'(whatsapp|message\b|msg\b|send\b|bhejo|bejo|bhej\b|likh\b|likho|likhna|paigham'
    r'|\u0648\u0627\u0679\u0633'            // واٹس  (correct U+0679 ٹ)
    r'|\u0648\u0627\u0479\u0633'            // واٹس  (legacy U+0479 some TTS engines)
    r'|\u0648\u0627\u062A\u0633'            // واتس  (alternate spelling)
    r'|\u0645\u06CC\u0633\u062C'            // میسج  (message)
    r'|\u0628\u06BE\u06CC\u062C\u0648'     // بھیجو (bhejo/send)
    r'|\u0628\u06BE\u06CC\u062C\u0646\u0627' // بھیجنا (bhejna)
    r'|\u0628\u06BE\u06CC\u062C'            // بھیج  (bhej — short form)
    r'|\u0644\u06A9\u06BE\u0648'            // لکھو  (likho/write)
    r'|\u0644\u06A9\u06BE'                  // لکھ   (likh — short form)
    r'|\u067E\u06CC\u063A\u0627\u0645'     // پیغام (paigham/message)
    r'|\u0627\u0631\u0633\u0627\u0644'     // ارسال (send/irsal)
    r'|\u0646\u0645\u0628\u0631'            // نمبر  (number — "X ka number do")
    r')',
    caseSensitive: false,
  );
  // Regex to extract a person's name — supports Latin AND Urdu/Arabic script
  // Connector words include both Roman Urdu and Urdu script equivalents.
  static final _nameExtractRegex = RegExp(
    r'''(?:^|[\s,])([\u0600-\u06FFa-zA-Z][\u0600-\u06FFa-zA-Z\s]{1,30}?)\s+(?:ko|par|per|ka|ke|se|wala|wale|number|ko\s+whatsapp|ko\s+message|\u06A9\u0648|\u06A9\u0627|\u0633\u06D2|\u067E\u0631|\u0646\u0645\u0628\u0631|\u06A9\u0648\s+\u0648\u0627\u0679\u0633|\u06A9\u0648\s+\u0645\u06CC\u0633\u062C)''',
    caseSensitive: false,
  );
  // Regex to detect item-availability / product search queries.
  // IMPORTANT: The original broad Urdu-script catch-all |[\u0621-\u06FF]{3,} has been
  // REMOVED — it caused all Urdu voice input to be flagged as an "item query", which
  // blocked the WhatsApp contact popup entirely for any Urdu speech.
  // Only explicit Roman-Urdu / English item keywords are matched here.
  static final _itemQueryRegex = RegExp(
    r'\b(hai|hy|hai\s+ya\s+n[ah]+i|status|available|pending|check|dekho|mila|milega|aaya|aya|stock|qty|quantity'
    r'|kahan|kab|kitna|kitnay|dhundo|search|find|batao|show|list|item|product|saman|samaan'
    r'|nahi\s+hai|nahi\s+mila|kya\s+hai|kya\s+hy|chahiye|chahie|lao|mangao|order)\b',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _typingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _micPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _micPulseAnim = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _micPulseController, curve: Curves.easeInOut),
    );
    _svc.ensureWelcome();
    _tryLoadContacts();
    // FIX: Speech engine initialized ONLY when mic button is tapped
    // (after microphone permission is explicitly granted by user)
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // UNLIMITED NAME MATCHING SYSTEM
  // Works for ANY name — Urdu script, Roman Urdu, English — with NO static list.
  // Pipeline: Urdu script → Roman → phonetic normalize → fuzzy Levenshtein match
  // ══════════════════════════════════════════════════════════════════════════════

  // Complete Urdu/Arabic character → Roman transliteration table.
  // Every possible Urdu letter is mapped, so ANY name in Urdu script
  // can be converted to an approximate Roman form algorithmically.
  static const Map<String, String> _urduCharToRoman = {
    // Alef variants
    'ا': 'a',  'آ': 'aa', 'أ': 'a',  'إ': 'i',  'ٱ': 'a',
    // Ba, Pa, Ta, Tta, Tha
    'ب': 'b',  'پ': 'p',
    'ت': 't',  'ٹ': 't',  'ث': 's',
    // Jeem, Chay, Ha, Kha
    'ج': 'j',  'چ': 'ch', 'ح': 'h',  'خ': 'kh',
    // Dal, Ddal, Zal
    'د': 'd',  'ڈ': 'd',  'ذ': 'z',
    // Ra, Rra, Zay, Zhay
    'ر': 'r',  'ڑ': 'r',  'ز': 'z',  'ژ': 'zh',
    // Sin, Shin, Sad, Dad
    'س': 's',  'ش': 'sh', 'ص': 's',  'ض': 'z',
    // Tay, Zay (emphatic)
    'ط': 't',  'ظ': 'z',
    // Ain, Ghain
    'ع': 'a',  'غ': 'gh',
    // Fa, Qaf, Kaf, Gaf
    'ف': 'f',  'ق': 'q',  'ک': 'k',  'گ': 'g',
    // Lam, Meem
    'ل': 'l',  'م': 'm',
    // Noon, Noon Ghunna
    'ن': 'n',  'ں': 'n',  'ڻ': 'n',
    // Waw, Ha, Ha (alternate), Ta Marbuta
    'و': 'w',  'ہ': 'h',  'ھ': 'h',  'ۃ': 'h',  'ة': 'h',
    // Hamza variants
    'ء': '',   'ئ': 'y',  'ؤ': 'w',
    // Ya, Ye, Ye (alternate)
    'ی': 'y',  'ے': 'ay', 'ۓ': 'ay',
    // Diacritics — strip completely
    '\u064E': '', '\u064F': '', '\u0650': '', '\u0651': '',
    '\u0652': '', '\u0653': '', '\u0654': '', '\u0655': '',
    '\u0656': '', '\u0657': '', '\u0658': '', '\u0670': '',
    '\u06E1': '', '\u06DF': '', '\u06E0': '',
  };

  // Convert any Urdu/Arabic script text to approximate Roman Urdu.
  // Works for names never seen before — purely algorithmic.
  static String _transliterateUrduToRoman(String text) {
    final buf = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (_urduCharToRoman.containsKey(ch)) {
        buf.write(_urduCharToRoman[ch]);
      } else if (rune >= 0x0600 && rune <= 0x06FF) {
        // Unknown Urdu/Arabic codepoint — skip silently
      } else {
        buf.write(ch); // Keep Latin, digits, spaces as-is
      }
    }
    return buf.toString().trim();
  }

  // Normalize a Roman Urdu / English name to a canonical phonetic form.
  // DESIGN: Only digraph/multi-char normalizations — NO single-char o→u/e→i/y→i
  // replacements. Those caused every short contact name ("S","Y","Z") to become a
  // false positive. Vowel equivalence is handled via consonant skeleton (tier 3).
  static String _normalizePhonetic(String s) {
    String n = s.toLowerCase().trim();
    // Strip digits and punctuation — keep only letters and spaces
    n = n.replaceAll(RegExp(r'[^a-z\s]'), '').trim();
    if (n.isEmpty) return '';
    // Digraph normalizations (longer patterns must come before shorter ones)
    n = n
        .replaceAll('kh', 'k')    // Khalid/Kalid
        .replaceAll('gh', 'g')    // Ghani/Gani
        .replaceAll('sh', 'x')    // sh → 'x' (unique placeholder avoids re-matching)
        .replaceAll('ch', 'c')    // Chand
        .replaceAll('zh', 'z')
        .replaceAll('ph', 'f')    // Zulfiqar
        .replaceAll('wh', 'w');
    // Long-vowel collapse (retain distinct vowels — don't collapse o≡u or e≡i here)
    n = n
        .replaceAll('aa', 'a')    // Saad/Sad, Kamraan/Kamran
        .replaceAll('oo', 'o')    // Noorani/Norani
        .replaceAll('ee', 'e')    // Naveed/Naved, Rasheed/Rashid form
        .replaceAll('uu', 'u')
        .replaceAll('ii', 'i');
    // Targeted diphthong normalization
    n = n
        .replaceAll('ay', 'ai')   // Faysal → Faisal form; keeps symmetry
        .replaceAll('au', 'a')    // Aurangzeb
        .replaceAll('aw', 'a');   // Nawaz → naz form
    // Collapse ONLY double consonants (not double vowels)
    // Hussain→Husain, Hassan→Hasan, Bilaal→Bilal
    n = n.replaceAllMapped(RegExp(r'([^aeiou\s])\1+'), (m) => m.group(1)!);
    return n.trim();
  }

  // Extract consonant skeleton — strips all vowels for deepest fuzzy match.
  // "Muhammad" → "mhmd", "Mohammed" → "mhmd" — both match.
  static String _consonantSkeleton(String normalized) {
    return normalized.replaceAll(RegExp(r'[aeiou\s]'), '');
  }

  // Levenshtein edit distance — used as last-resort fuzzy match.
  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = a.length, n = b.length;
    // Use two-row rolling array to save memory
    var prev = List<int>.generate(n + 1, (j) => j);
    var curr = List<int>.filled(n + 1, 0);
    for (int i = 1; i <= m; i++) {
      curr[0] = i;
      for (int j = 1; j <= n; j++) {
        curr[j] = a[i - 1] == b[j - 1]
            ? prev[j - 1]
            : 1 + [prev[j], curr[j - 1], prev[j - 1]].reduce((x, y) => x < y ? x : y);
      }
      final tmp = prev; prev = curr; curr = tmp;
    }
    return prev[n];
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PROFESSIONAL MULTI-LANGUAGE CONTACT SEARCH
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Strategy: expand BOTH the query AND every contact name into ALL possible
  // forms across English / Roman-Urdu / Urdu-script, then match any form
  // against any form.
  //
  //  Tier A  — substring match on all romanised/normalised forms
  //  Tier B  — consonant-skeleton equality with length-ratio guard + Levenshtein
  //
  // ── Name-variants dictionary — 160+ common Pakistani name groups ──────────
  // Each inner list = every known English/Roman-Urdu spelling of ONE name.
  // Used to expand the query to all sibling forms so a search for "Ismail"
  // also hits contacts stored as "Ismaeel", "Ismayil", etc. and vice-versa.
  static const List<List<String>> _nameVariants = [
    // Male first names
    ['muhammad','mohammed','mohd','muhamad','mohamad','mehmed'],
    ['ahmad','ahmed','ahamed'],
    ['ali','aly','alee'],
    ['usman','osman','uthman','usmaan'],
    ['ismail','ismaeel','ismael','esmail','ismayil','ismayl'],
    ['ramzan','ramazan','ramadan','ramzaan','ramdhan'],
    ['hassan','hasan','hussan','hasaan'],
    ['hussain','husain','hussein','husein','hosain'],
    ['khalid','khaled','calid','kalid','khaalid'],
    ['rashid','rasheed','rashed'],
    ['naveed','naved','navid','naweed'],
    ['faisal','faysal','feisal','faissal'],
    ['bilal','bilaal','belal','billal'],
    ['tariq','tarique','tarik'],
    ['asif','assef','aasif'],
    ['amir','ameer','aamir','aamer'],
    ['zahid','zaheed','zaahid'],
    ['sohail','suhail','sohayl','suhayl'],
    ['imran','emran','imraan'],
    ['adnan','adnaan'],
    ['irfan','erfan','irfaan'],
    ['salman','salmaan'],
    ['kamran','kamraan','kamron'],
    ['zafar','zuffer','zafur'],
    ['rizwan','rizwaan'],
    ['waqar','waqaar','wakar'],
    ['waseem','wasim'],
    ['arif','aarif','ariff'],
    ['naseer','nasir','naser','naaseer'],
    ['shakeel','shakil','shaqeel'],
    ['saeed','said','sayeed','saied'],
    ['shahid','shaheed'],
    ['zaheer','zahir'],
    ['raza','rezza','reza'],
    ['asad','asaad'],
    ['ahsan','ahsaan','ihsan','ehsan'],
    ['iqbal','iqbaal'],
    ['pervaiz','pervez','perwaiz','parvaiz'],
    ['babar','babur','babbar'],
    ['zubair','zuber','zubayer'],
    ['jameel','jamil'],
    ['majid','majeed'],
    ['tahir','taheer'],
    ['hamid','hameed'],
    ['noman','nouman','noumaan'],
    ['yasir','yasser','yaseer'],
    ['awais','owais','ovais'],
    ['qasim','kasim','qaasim'],
    ['farhan','farhaan'],
    ['danish','daanish'],
    ['umer','umar','omar','omer'],
    ['farooq','faruq','faruk'],
    ['shoaib','shuaib','shuayb'],
    ['haris','harris','haaris'],
    ['zohaib','zuhaib','zoheb'],
    ['talha','talha'],
    ['muzammil','muzamil','muzzamil'],
    ['saad','sad'],
    ['zaid','zayd','zayed'],
    ['haroon','harun','haroun'],
    ['yousaf','yusuf','yousuf','yousof'],
    ['umair','umayer','umaire'],
    ['shehzad','shahzad'],
    ['fawad','fawwad','fawaad'],
    ['naeem','naim'],
    ['rehan','rayhan'],
    ['kamil','kaamil'],
    ['kamal','kamaal'],
    ['saleem','salim'],
    ['murad','murrad'],
    ['javed','javaid','jawed','jawaid'],
    ['azhar','azher'],
    ['ijaz','ejaz'],
    ['mukhtar','mukhtaar'],
    ['ghulam','ghulaam'],
    ['sajid','saajid','sajjid'],
    ['mubashir','mubasheer'],
    ['wajid','waajid'],
    ['saif','sayf'],
    ['nadir','naadir'],
    ['asim','aasim','aseem'],
    ['kashif','kaashif'],
    ['waheed','wahid'],
    ['akram','akraam'],
    ['anwar','anwaar','anver'],
    ['aftab','aftaab'],
    ['shafiq','shafeeq'],
    ['nadeem','nadim'],
    ['aslam','asllam'],
    ['tanveer','tanvir','tanweer'],
    ['raees','rais'],
    ['fazal','fazl'],
    ['ikram','ikraam'],
    ['habib','habeeb'],
    ['idrees','idris'],
    ['rafiq','rafiiq','rafeeq'],
    ['riaz','riyaz','riyaaz'],
    ['mannan','manan'],
    ['aziz','azeez'],
    ['latif','lateef'],
    ['anees','anis'],
    ['sabir','saaber'],
    ['manzoor','manzur'],
    ['nisar','nisaar','nissar'],
    // Female first names
    ['fatima','fatimah','fatema'],
    ['ayesha','aisha','aaisha','aesha','aysha'],
    ['zainab','zaynab','zeynep'],
    ['sana','sanaa'],
    ['maryam','mariam','maria','marium'],
    ['sara','sarah','saara'],
    ['hina','heena','hena','hinna'],
    ['nadia','naadia'],
    ['amna','aamna'],
    ['rabia','rabiya','rabea'],
    ['mehwish','mahwish','mehvish'],
    ['sadia','sadiya'],
    ['asma','aasma'],
    ['samina','sameena'],
    ['tahira','tahera'],
    ['shabana'],
    ['uzma','uzzma'],
    ['rubina','rubeena','robeena'],
    ['shaista','shaysta'],
    ['saima','sayma'],
    ['farzana','farzaana'],
    ['bushra','buxra'],
    ['naila','nayla'],
    ['anum','anam','annum'],
    ['zara','zahra','zehra'],
    ['maham','mahum'],
    ['laiba','laeba','layba'],
    ['nimra','nimrah'],
    ['arooba','aroha'],
    ['zobia','zubia'],
    ['kiran','kirann','keren'],
    ['shazia','shaziya'],
    ['saba','saaba'],
    ['huma','hooma'],
    ['seema','sima','seema'],
    ['nargis','nargiss'],
    ['abida','abeeda'],
    // Surnames / family names
    ['qureshi','quraishi','quereshi'],
    ['malik','malick','maalik','mallick'],
    ['sheikh','shaikh','shaykh'],
    ['chaudhry','chaudhary','choudry','choudhary','choudhari'],
    ['butt','bhat','bhatt'],
    ['siddiqui','siddiqi','siddiqy'],
    ['mirza','meerza'],
    ['hashmi','hashimi'],
    ['ansari','ansaari'],
    ['abbasi','abbassi'],
    ['gilani','jelani'],
    ['awan','awaan'],
    ['rajput','rajpoot'],
    ['lodhi','lodi'],
    ['niazi','niyazi'],
    ['afridi','afreedi'],
    ['baig','beg','bayg'],
    ['rana','raana'],
    ['bhatti','bhatty','bhaty'],
    ['cheema','chima'],
    ['gondal'],
    ['tarar','tarrar'],
    ['khan','khaan'],
    ['pasha','paasha'],
    ['syed','sayyid','sayyed'],
    ['mughal','moghal'],
    ['arain','araeen'],
    ['khattak','khatak'],
    ['durrani','dorani'],
    ['gujjar','gujar'],
    ['tanoli','tanooli'],
  ];

  // ── Expand one word into ALL its searchable roman + skeleton forms ─────────
  // Used for both the query and each contact name word.
  static void _addWordForms(
    String word,
    Set<String> romanOut,
    Set<String> skelOut,
    bool expandVariants,
  ) {
    if (word.length < 2) return;
    final isUrdu = RegExp(r'[\u0600-\u06FF]').hasMatch(word);
    final roman = isUrdu
        ? _transliterateUrduToRoman(word).toLowerCase().trim()
        : word.toLowerCase();
    if (roman.length < 2) return;

    romanOut.add(roman);
    final norm = _normalizePhonetic(roman);
    if (norm.isNotEmpty) romanOut.add(norm);

    final sk = _consonantSkeleton(norm.isNotEmpty ? norm : roman);
    if (sk.length >= 2) {
      skelOut.add(sk);
      // Expand via name-variants table so "ismail" also generates "ismaeel", etc.
      if (expandVariants) {
        for (final group in _nameVariants) {
          bool inGroup = false;
          for (final v in group) {
            if (_consonantSkeleton(_normalizePhonetic(v)) == sk) {
              inGroup = true;
              break;
            }
          }
          if (inGroup) {
            for (final v in group) {
              romanOut.add(v.toLowerCase());
              final vn = _normalizePhonetic(v);
              if (vn.isNotEmpty) romanOut.add(vn);
              final vs = _consonantSkeleton(vn);
              if (vs.length >= 2) skelOut.add(vs);
            }
            break;
          }
        }
      }
    }
  }

  // ── All forms of the query (roman set + skeleton set) ─────────────────────
  static ({Set<String> roman, Set<String> skel}) _queryForms(String query) {
    final roman = <String>{};
    final skel  = <String>{};
    for (final word in query.trim().split(RegExp(r'\s+'))) {
      _addWordForms(word, roman, skel, true);
    }
    return (roman: roman, skel: skel);
  }

  // ── All forms of a contact name (roman set + skeleton set) ────────────────
  static ({Set<String> roman, Set<String> skel}) _contactForms(String name) {
    final roman = <String>{};
    final skel  = <String>{};
    // Full name as one unit (for full-name substring match)
    final hasUrdu = RegExp(r'[\u0600-\u06FF]').hasMatch(name);
    final fullRoman = hasUrdu
        ? _transliterateUrduToRoman(name).toLowerCase().trim()
        : name.toLowerCase();
    roman.add(fullRoman);
    // Word-level forms (for individual word matching)
    for (final word in fullRoman.split(RegExp(r'\s+'))) {
      _addWordForms(word, roman, skel, false);
    }
    return (roman: roman, skel: skel);
  }

  // ── Professional multi-language contact finder ────────────────────────────
  //
  // Both query AND each contact are expanded to ALL English / Roman-Urdu forms.
  // The _nameVariants table further expands to sibling spellings of known names.
  //
  //  Tier A — any contact roman-form contains any query roman-form (substring)
  //  Tier B — any contact skeleton matches any query skeleton (exact + Levenshtein
  //            with length-ratio guard to prevent short-name false positives)
  //
  List<PhoneContact> _smartFindContacts(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final allContacts = _contactsSvc.contacts;
    if (allContacts.isEmpty) return [];

    // Expand query into ALL possible English + Roman-Urdu forms + skeletons
    final qf     = _queryForms(trimmed);
    final qRoman = qf.roman;
    final qSkel  = qf.skel;
    if (qRoman.isEmpty && qSkel.isEmpty) return [];

    final results = <PhoneContact>[];
    final seen    = <String>{};

    for (final c in allContacts) {
      if (seen.contains(c.phone)) continue;

      // Expand contact into ALL matchable forms
      final cf     = _contactForms(c.name);
      final cRoman = cf.roman;
      final cSkel  = cf.skel;

      bool matched = false;

      // ── Tier A: substring on any roman/normalised form ──────────────────────
      // Contact form must CONTAIN query form — never the reverse.
      // Prevents short contact names ("S", "Y") from matching long queries.
      tierA:
      for (final qf2 in qRoman) {
        if (qf2.length < 2) continue;
        for (final cf2 in cRoman) {
          if (cf2.length < 2) continue;
          if (cf2.contains(qf2)) { matched = true; break tierA; }
        }
      }

      // ── Tier B: consonant-skeleton match with length-ratio + Levenshtein ───
      // Exact equality required for short skeletons (≤3 chars) — prevents
      // "smn" (Usman) from matching "sml" (Ismaeel).
      if (!matched) {
        tierB:
        for (final qs in qSkel) {
          if (qs.length < 2) continue;
          for (final cs in cSkel) {
            if (cs.length < 2) continue;
            final longer  = qs.length > cs.length ? qs.length : cs.length;
            final shorter = qs.length < cs.length ? qs.length : cs.length;
            if (shorter < longer * 0.6) continue; // length-ratio guard
            final maxD = qs.length <= 3 ? 0 : (qs.length <= 5 ? 1 : 2);
            if (_levenshtein(qs, cs) <= maxD) { matched = true; break tierB; }
          }
        }
      }

      if (matched) { seen.add(c.phone); results.add(c); }
    }
    return results;
  }

  // ── Static helper: check if a single contact name matches the query ────────
  // Extracted from _smartFindContacts so it can be used for arbitrary data sources
  // (customers, suppliers) without requiring a PhoneContact list.
  static bool _nameMatchesQuery(String query, String contactName) {
    if (query.trim().isEmpty || contactName.trim().isEmpty) return false;
    final qf = _queryForms(query.trim());
    final cf = _contactForms(contactName);

    // Tier A: substring on any romanised form
    for (final qf2 in qf.roman) {
      if (qf2.length < 2) continue;
      for (final cf2 in cf.roman) {
        if (cf2.length < 2) continue;
        if (cf2.contains(qf2)) return true;
      }
    }

    // Tier B: consonant-skeleton with length-ratio + Levenshtein
    for (final qs in qf.skel) {
      if (qs.length < 2) continue;
      for (final cs in cf.skel) {
        if (cs.length < 2) continue;
        final longer  = qs.length > cs.length ? qs.length : cs.length;
        final shorter = qs.length < cs.length ? qs.length : cs.length;
        if (shorter < longer * 0.6) continue;
        final maxD = qs.length <= 3 ? 0 : (qs.length <= 5 ? 1 : 2);
        if (_levenshtein(qs, cs) <= maxD) return true;
      }
    }
    return false;
  }

  // ── Search customers and suppliers from app data (Firestore providers) ─────
  //
  // Returns PhoneContact-compatible entries for any customer/supplier whose
  // name matches ANY of the given candidate query strings.
  // This lets the WhatsApp popup show contacts from the app database too,
  // not just from the device's phone book.
  List<PhoneContact> _findContactsInAppData(List<String> candidates) {
    final results = <PhoneContact>[];
    final seen = <String>{};

    void add(String name, String phone, String tag) {
      final clean = phone.trim().replaceAll(RegExp(r'[\s\-()]'), '');
      if (clean.isEmpty || seen.contains(clean)) return;
      seen.add(clean);
      results.add(PhoneContact(name: '$name ($tag)', phone: clean));
    }

    // ── Search customers ───────────────────────────────────────────────────
    try {
      final custProv = context.read<CustomerProvider>();
      for (final c in custProv.all) {
        if (c.name.isEmpty) continue;
        final match = candidates.any((q) => _nameMatchesQuery(q, c.name));
        if (!match) continue;
        if (c.whatsappNumber.isNotEmpty) add(c.name, c.whatsappNumber, 'Customer WA');
        if (c.phone.isNotEmpty && c.phone != c.whatsappNumber) {
          add(c.name, c.phone, 'Customer');
        }
      }
    } catch (_) {}

    // ── Search suppliers ───────────────────────────────────────────────────
    try {
      final suppProv = context.read<SupplierProvider>();
      for (final s in suppProv.all) {
        if (s.name.isEmpty) continue;
        // Match by supplier name OR company name
        final match = candidates.any(
            (q) => _nameMatchesQuery(q, s.name) || _nameMatchesQuery(q, s.company));
        if (!match) continue;
        if (s.whatsappNumber.isNotEmpty) add(s.name, s.whatsappNumber, 'Supplier WA');
        if (s.phoneNumber.isNotEmpty) add(s.name, s.phoneNumber, 'Supplier Ph');
        for (final extra in s.additionalNumbers) {
          if (extra.number.isNotEmpty) {
            add(s.name, extra.number, 'Supplier ${extra.displayLabel}');
          }
        }
      }
    } catch (_) {}

    return results;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UNLIMITED PRODUCT SEARCH — Urdu / Roman-Urdu / English
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Three-layer matching:
  //   Layer 1 — Semantic synonym map  (Urdu concept → English term)
  //   Layer 2 — Phonetic skeleton match (same-language variants, typos)
  //   Layer 3 — Urdu-script transliteration (if item stored in Urdu script)
  //
  // ── Comprehensive semantic map — 300+ Urdu/Roman-Urdu → English entries ─
  // Roman Urdu key → list of English/Roman-Urdu search terms.
  // Urdu words in the user query are first transliterated then looked up here.
  static const Map<String, List<String>> _productSynonyms = {
    // ── Grains & Rice ───────────────────────────────────────────────────────
    'chawal':['rice','basmati','kala zeera','sella','parboiled'],
    'chaawal':['rice','basmati'],
    'basmati':['rice','basmati','long grain'],
    'sella':['sella rice','parboiled','rice'],
    'gehu':['wheat','flour','atta','whole wheat'],
    'gehun':['wheat','flour','atta'],
    'atta':['flour','wheat','atta','whole wheat','chakki'],
    'maida':['flour','maida','refined flour','all purpose flour'],
    'sooji':['semolina','sooji','rawa','suji'],
    'suji':['semolina','sooji','rawa'],
    'rawa':['semolina','sooji','suji'],
    'besan':['gram flour','chickpea flour','besan'],
    'corn':['corn flour','maize','cornstarch','makkai'],
    'makkai':['corn','maize','corn flour'],
    'oat':['oats','oatmeal','quaker'],
    'daliya':['porridge','oats','bran','daliya'],
    'bran':['bran','whole wheat','fiber'],
    // ── Pulses & Lentils ────────────────────────────────────────────────────
    'daal':['lentil','dal','masoor','chana','mung','moong','urad','toor'],
    'dal':['lentil','daal','masoor','chana','mung','moong'],
    'masoor':['masoor','lentil','red lentil','daal'],
    'chana':['chana','chickpea','gram','kabuli','daal'],
    'kabuli':['kabuli chana','chickpea','white chana'],
    'moong':['moong','mung','green gram','lentil'],
    'mung':['moong','mung','green gram'],
    'mash':['mash','urad','white lentil','daal'],
    'urad':['urad','urad dal','black gram'],
    'toor':['toor','arhar','pigeon pea','daal'],
    'arhar':['arhar','toor','pigeon pea'],
    'rajma':['rajma','kidney bean','red bean'],
    // ── Oils & Fats ─────────────────────────────────────────────────────────
    'ghee':['ghee','clarified butter','desi ghee'],
    'tel':['oil','cooking oil','sunflower','canola','soya'],
    'teel':['sesame','til','sesame oil'],
    'makkhan':['butter','makkhan','margarine','spread'],
    'dalda':['dalda','vegetable ghee','vanaspati'],
    'vanaspati':['vanaspati','dalda','vegetable oil'],
    'sunflower':['sunflower oil','cooking oil'],
    'canola':['canola oil','cooking oil'],
    'olive':['olive oil','zaitoon'],
    'zaitoon':['olive','olive oil'],
    // ── Sugar, Salt & Sweeteners ────────────────────────────────────────────
    'cheeni':['sugar','white sugar','shakkar','caster'],
    'shakkar':['sugar','brown sugar','cheeni','gur'],
    'gur':['jaggery','gur','brown sugar','shakkar'],
    'namak':['salt','table salt','sodium','iodized'],
    'kala namak':['black salt','rock salt','pink salt'],
    'sendha namak':['rock salt','himalayan salt','pink salt'],
    'shaker':['sugar','shakkar','cheeni'],
    // ── Spices & Masala ─────────────────────────────────────────────────────
    'mirch':['pepper','chilli','chili','red pepper','green chilli'],
    'lal mirch':['red chilli','red pepper','cayenne'],
    'hari mirch':['green chilli','green pepper'],
    'kali mirch':['black pepper','peppercorn'],
    'haldi':['turmeric','haldi powder','yellow spice'],
    'zeera':['cumin','zeera','cumin seeds','caraway'],
    'zira':['cumin','zeera'],
    'kala zeera':['black cumin','nigella','kalonji'],
    'kalonji':['nigella','onion seeds','black cumin'],
    'dhania':['coriander','cilantro','coriander seeds'],
    'saunf':['fennel','aniseed','saunf'],
    'methi':['fenugreek','methi seeds','kasuri methi'],
    'ajwain':['carom seeds','thymol','ajwain'],
    'laung':['cloves','laung'],
    'darchini':['cinnamon','dalchini'],
    'dalchini':['cinnamon','darchini'],
    'elaichi':['cardamom','green cardamom','elaichi'],
    'bari elaichi':['black cardamom','moti elaichi'],
    'jaifal':['nutmeg','jaifal'],
    'chakri phool':['star anise','chakri'],
    'bay patta':['bay leaf','tej patta'],
    'adrak':['ginger','fresh ginger','adrak powder'],
    'lehsan':['garlic','garlic powder','lehsan paste'],
    'lasan':['garlic','lehsan','garlic paste'],
    'pyaz':['onion','onion powder','dried onion'],
    'tamatar':['tomato','tomatoes','tomato paste'],
    'masala':['spice','masala','spice mix','blend'],
    'biryani masala':['biryani','biryani spice'],
    'karahi masala':['karahi','stir fry spice'],
    'tikka masala':['tikka','bbq masala'],
    'nihari masala':['nihari','stew spice'],
    'haleem masala':['haleem'],
    'chat masala':['chaat','chutney spice'],
    'garam masala':['garam masala','mixed spice'],
    'keema masala':['mince','keema spice'],
    'meat masala':['meat spice','gosht masala'],
    'shami masala':['shami kabab'],
    'pulao masala':['pulao','rice spice'],
    'sabji masala':['vegetable spice','curry masala'],
    // ── Vegetables ──────────────────────────────────────────────────────────
    'aloo':['potato','potatoes','chips'],
    'matar':['peas','green peas','mutter'],
    'gajar':['carrot','carrots'],
    'palak':['spinach','paalak'],
    'gobi':['cauliflower','cabbage','gobhi'],
    'band gobi':['cabbage','head cabbage'],
    'phool gobi':['cauliflower'],
    'baingan':['eggplant','brinjal','aubergine'],
    'tinda':['round gourd','apple gourd'],
    'tori':['zucchini','courgette','ridge gourd'],
    'kaddu':['pumpkin','squash','butternut'],
    'lauki':['bottle gourd','doodhi'],
    'karela':['bitter gourd','bitter melon'],
    'shalgam':['turnip'],
    'mooli':['radish','daikon'],
    'kheera':['cucumber','cucumbers'],
    'bhindi':['okra','ladyfinger'],
    'sem':['green beans','string beans'],
    'arbi':['taro','colocasia'],
    // ── Dairy & Eggs ────────────────────────────────────────────────────────
    'doodh':['milk','dairy','powder milk','full cream','skimmed'],
    'dahi':['yogurt','yoghurt','curd','plain yogurt'],
    'paneer':['paneer','cottage cheese','cheese'],
    'khoya':['khoya','mawa','evaporated milk','solid milk'],
    'mawa':['mawa','khoya'],
    'cream':['cream','fresh cream','whipping cream','malai'],
    'malai':['cream','clotted cream','malai'],
    'anda':['egg','eggs','poultry'],
    'anday':['eggs','egg','poultry'],
    'lassi':['yogurt drink','lassi','buttermilk'],
    'makhan':['butter','makkhan'],
    // ── Meat & Poultry ──────────────────────────────────────────────────────
    'gosht':['meat','mutton','beef','lamb'],
    'murghi':['chicken','poultry','hen'],
    'chicken':['chicken','murghi','poultry'],
    'beef':['beef','gosht','meat'],
    'mutton':['mutton','lamb','gosht'],
    'machli':['fish','seafood'],
    'jheenga':['shrimp','prawn','seafood'],
    'keema':['mince','minced meat','ground beef'],
    'qeema':['mince','minced meat','ground beef'],
    'kaleji':['liver','offal'],
    // ── Bread & Baked Goods ─────────────────────────────────────────────────
    'roti':['bread','chapati','roti','flatbread'],
    'naan':['naan','bread','leavened bread'],
    'pao':['bun','bread roll','bread'],
    'bread':['bread','roti','naan','sandwich bread','toast'],
    'biscuit':['biscuit','cookie','crackers','digestive'],
    'cake':['cake','sponge','pastry'],
    'rusks':['rusk','toast','dry bread'],
    'paratha':['paratha','flatbread'],
    // ── Drinks & Beverages ──────────────────────────────────────────────────
    'chai':['tea','green tea','black tea','herbal tea','doodh patti'],
    'green tea':['green tea','chai'],
    'coffee':['coffee','instant coffee','espresso','latte'],
    'pani':['water','mineral water','drinking water','bottled water'],
    'juice':['juice','fruit juice','drink','nectar'],
    'sharbat':['syrup','cordial','squash','rooh afza'],
    'rooh afza':['rooh afza','sharbat','drink'],
    'cola':['cola','soda','fizzy drink','coke','pepsi'],
    'cold drink':['soda','cola','fizzy','cold drink'],
    'energy drink':['energy drink','boost','power'],
    'milk shake':['milkshake','shake','flavored milk'],
    // ── Condiments & Sauces ─────────────────────────────────────────────────
    'sirka':['vinegar','sirka'],
    'imli':['tamarind','imli paste'],
    'ketchup':['ketchup','tomato sauce','tomato ketchup'],
    'mayonnaise':['mayonnaise','mayo'],
    'chutney':['chutney','sauce','dip'],
    'achaar':['pickle','achar','mixed pickle'],
    'achar':['pickle','achaar','chilli pickle'],
    'jam':['jam','jelly','marmalade','preserve'],
    'honey':['honey','shehad'],
    'shehad':['honey','natural honey'],
    'soya sauce':['soya sauce','soy sauce'],
    'hot sauce':['hot sauce','chilli sauce','mirch sauce'],
    // ── Snacks & Dry Fruits ─────────────────────────────────────────────────
    'chips':['chips','crisps','snacks','wafers'],
    'namkeen':['namkeen','savory snacks','mixture'],
    'mixture':['mixture','namkeen','snack mix'],
    'popcorn':['popcorn','corn'],
    'mewa':['dry fruit','dried fruit','nuts'],
    'dry fruit':['dry fruit','mewa','nuts'],
    'badam':['almond','almonds','badam'],
    'pista':['pistachio','pista'],
    'akhrot':['walnut','walnuts'],
    'kishmish':['raisins','dried grapes','sultana'],
    'khajoor':['dates','khajoor','dried dates'],
    'munakka':['black raisin','dried grape'],
    'anjeer':['fig','dried fig'],
    'chilgoza':['pine nuts','chilgoza'],
    'kaju':['cashew','cashew nuts'],
    'mungphali':['peanut','groundnut','peanuts'],
    // ── Household & Cleaning ────────────────────────────────────────────────
    'sabun':['soap','hand wash','bar soap','bathing soap'],
    'surf':['detergent','washing powder','surf excel','ariel'],
    'ariel':['detergent','ariel','washing powder'],
    'rin':['detergent','rin','washing powder'],
    'washing':['washing powder','detergent','laundry'],
    'dishwash':['dishwash','dish soap','vim','scotch'],
    'vim':['dishwash','vim','scourer'],
    'shampoo':['shampoo','hair wash','hair care'],
    'conditioner':['conditioner','hair conditioner'],
    'toothpaste':['toothpaste','tooth paste','dental'],
    'brush':['toothbrush','brush'],
    'dettol':['dettol','antiseptic','disinfectant'],
    'bleach':['bleach','chlorine','disinfectant'],
    'tissue':['tissue','tissue paper','kleenex'],
    'toilet paper':['toilet paper','tissue','bathroom tissue'],
    'napkin':['napkin','tissue','serviette'],
    'broom':['broom','jharoo','sweep'],
    'mop':['mop','floor cleaner'],
    'garbage bag':['garbage bag','dustbin bag','trash bag'],
    // ── Baby & Health ───────────────────────────────────────────────────────
    'dawa':['medicine','tablet','syrup','capsule','pill'],
    'dawai':['medicine','dawa','tablet','syrup'],
    'panadol':['panadol','paracetamol','pain relief'],
    'diaper':['diaper','nappy','pamper','huggies'],
    'pamper':['diaper','pamper','nappy'],
    'baby food':['baby food','cerelac','infant formula'],
    'cerelac':['cerelac','baby food','infant cereal'],
    'multivitamin':['vitamin','supplement','multivitamin'],
    // ── Plastic & Packaging ─────────────────────────────────────────────────
    'polythene':['polythene','plastic bag','shopping bag'],
    'bag':['bag','polythene','plastic','shopping bag'],
    'container':['container','box','tiffin','food container'],
    'bottle':['bottle','water bottle','plastic bottle'],
    // ── Frozen & Processed ─────────────────────────────────────────────────
    'frozen':['frozen','icecream','frozen food'],
    'ice cream':['ice cream','icecream','kulfi','frozen dessert'],
    'kulfi':['kulfi','ice cream','frozen dessert'],
    'french fries':['french fries','fries','frozen potato'],
    'nuggets':['nuggets','chicken nuggets','frozen chicken'],
    'sausage':['sausage','hot dog','processed meat'],
    'burger':['burger','burger patty','bun'],
  };

  // ── Extract candidate names — regex first, then word-by-word fallback ──────
  // This handles both Latin (Ali) and Urdu script (علی) voice recognition output.
  List<String> _extractNameCandidates(String text) {
    final candidates = <String>[];

    // Strategy 1: regex-based extraction
    final match = _nameExtractRegex.firstMatch(text);
    if (match != null) {
      final name = match.group(1)?.trim();
      if (name != null && name.length >= 2) candidates.add(name);
    }

    if (candidates.isNotEmpty) return candidates;

    // Strategy 2: word-by-word fallback (Urdu/romanized Urdu often has no
    // standard connector words before the name, e.g. "Ali ka number" gives "Ali")
    // Includes Urdu script stop words so WhatsApp/message words aren't picked as names.
    const stopWords = {
      // ── Roman Urdu / English connectors ────────────────────────────────────
      'ko', 'ka', 'ki', 'ke', 'par', 'per', 'se', 'hai', 'hain', 'hy',
      'karo', 'do', 'dena', 'bata', 'batao', 'wala', 'wali', 'number',
      'whatsapp', 'message', 'send', 'contact', 'aur', 'ya', 'msg',
      'nhi', 'nahi', 'check', 'kya', 'mujhe', 'ap', 'aap', 'mera', 'tera',
      'uska', 'call', 'next', 'kro', 'krna',
      // Roman Urdu sending/writing words
      'bhejo', 'bejo', 'bhej', 'likh', 'likho', 'likhna', 'paigham',
      // English filler words
      'the', 'a', 'an', 'in', 'on', 'at', 'to', 'for', 'of', 'and',
      'or', 'is', 'was', 'are', 'were',
      // ── Item/product query words ─────────────────────────────────────────
      'search', 'find', 'dhundo', 'item', 'product',
      'show', 'list', 'dekho', 'kitna', 'kitnay', 'kahan', 'kab', 'status',
      // ── Urdu script: connectors ──────────────────────────────────────────
      '\u06A9\u0648',   // کو  (ko)
      '\u06A9\u0627',   // کا  (ka)
      '\u06A9\u06CC',   // کی  (ki)
      '\u06A9\u06D2',   // کے  (ke)
      '\u0633\u06D2',   // سے  (se)
      '\u067E\u0631',   // پر  (par)
      // ── Urdu script: WhatsApp / messaging words ──────────────────────────
      '\u0648\u0627\u0679\u0633',             // واٹس (WhatsApp — U+0679 correct)
      '\u0648\u0627\u0479\u0633',             // واٹس (WhatsApp — U+0479 legacy TTS)
      '\u0648\u0627\u062A\u0633',             // واتس (alternate spelling)
      '\u0627\u06CC\u067E',                   // ایپ  (app)
      '\u0645\u06CC\u0633\u062C',             // میسج (message)
      '\u0628\u06BE\u06CC\u062C\u0648',       // بھیجو (bhejo)
      '\u0628\u06BE\u06CC\u062C\u0646\u0627', // بھیجنا (bhejna)
      '\u0628\u06BE\u06CC\u062C\u0646\u06D2', // بھیجنے (bhejne)
      '\u0628\u06BE\u06CC\u062C',             // بھیج  (bhej — short form)
      '\u0644\u06A9\u06BE\u0648',             // لکھو  (likho/write)
      '\u0644\u06A9\u06BE',                   // لکھ   (likh — short form)
      '\u067E\u06CC\u063A\u0627\u0645',       // پیغام (paigham/message)
      '\u0627\u0631\u0633\u0627\u0644',       // ارسال (send/irsal)
      // ── Urdu script: action / filler words ──────────────────────────────
      '\u06A9\u0631\u0648',                   // کرو  (karo)
      '\u06A9\u0631\u0646\u0627',             // کرنا (karna)
      '\u06A9\u0631\u06CC\u06BA',             // کریں (karen)
      '\u06A9\u0627\u0644',                   // کال  (call)
      '\u0641\u0648\u0646',                   // فون  (phone)
      '\u0631\u0627\u0628\u0637\u06C1',       // رابطہ (contact)
      '\u0646\u06C1\u06CC\u06BA',             // نہیں (nahi)
      '\u06C1\u06D2',                         // ہے   (hai)
      '\u06C1\u06CC\u06BA',                   // ہیں  (hain)
      '\u0627\u0648\u0631',                   // اور  (aur)
      '\u06CC\u0627',                         // یا   (ya)
      '\u0686\u06CC\u06A9',                   // چیک  (check)
      // ── Urdu script: number-related ─────────────────────────────────────
      '\u0646\u0645\u0628\u0631',             // نمبر (number)
      '\u062F\u0648',                         // دو   (do/give)
      '\u062F\u06CC\u06BA',                   // دیں  (dain/give)
      '\u0628\u062A\u0627\u0626\u06CC\u06BA', // بتائیں (batain/tell)
    };
    final words = text.split(RegExp(r'[\s,؟?।]+'));
    for (final word in words) {
      final w = word.trim();
      if (w.length >= 2 && !stopWords.contains(w.toLowerCase())) {
        candidates.add(w);
      }
    }
    return candidates;
  }

  // ── Extract only contacts relevant to THIS message — max 10 ─────────────────
  // Searches phone contacts AND app data (customers / suppliers).
  List<Map<String, dynamic>> _getRelevantContacts(String message) {
    if (!_waIntentRegex.hasMatch(message)) return [];
    if (_itemQueryRegex.hasMatch(message) && !_definiteWaRegex.hasMatch(message)) return [];

    final candidates = _extractNameCandidates(message);
    if (candidates.isEmpty) return [];

    final seen = <String>{};
    final results = <PhoneContact>[];

    // 1. Phone contacts (if loaded)
    if (_contactsSvc.isLoaded) {
      for (final name in candidates) {
        for (final c in _smartFindContacts(name)) {
          if (!seen.contains(c.phone)) {
            seen.add(c.phone);
            results.add(c);
          }
        }
        if (results.length >= 10) break;
      }
    }

    // 2. App data: customers + suppliers (always available)
    if (results.length < 10) {
      for (final c in _findContactsInAppData(candidates)) {
        if (!seen.contains(c.phone)) {
          seen.add(c.phone);
          results.add(c);
        }
        if (results.length >= 10) break;
      }
    }

    return results.take(10).map((c) => c.toMap()).toList();
  }

  // ── UNLIMITED Product Search — Urdu / Roman-Urdu / English ──────────────────
  //
  // Layer 1 — Semantic synonym map: "chawal" → ["rice","basmati"] and reverse
  // Layer 2 — Phonetic skeleton: catches typos / alternate spellings of same word
  // Layer 3 — Urdu-script transliteration: item stored as "چاول" matches "chawal"
  //
  // The three layers work together so ANY Urdu product name, in any script or
  // spelling variant, finds its matching items — no static list can limit it.
  List<DemandItemModel> _searchLocalItems(
      List<DemandItemModel> allItems, String query) {
    // Skip broad list queries — backend handles those
    if (RegExp(r'\b(sari|saari|list|sab|all|pending\s+items|urgent\s+items|show\s+all)\b',
            caseSensitive: false)
        .hasMatch(query)) {
      return [];
    }

    const stopWords = {
      'ko', 'ka', 'ki', 'ke', 'par', 'se', 'hai', 'hain', 'hy', 'kya',
      'status', 'item', 'check', 'dekho', 'available', 'pending',
      'aur', 'ya', 'nhi', 'nahi', 'aya', 'aaya', 'mila', 'milega',
      'chahiye', 'chahie', 'lao', 'kahan', 'kab', 'kitna', 'kitnay',
      'show', 'find', 'search', 'dhundo', 'batao', 'the', 'a', 'an',
      'is', 'are', 'what', 'how', 'much', 'many', 'any',
    };

    // Extract meaningful words from the query
    final rawWords = query
        .split(RegExp(r'[\s,؟?।]+'))
        .map((w) => w.trim().replaceAll(RegExp(r'[?!.,؟]'), ''))
        .where((w) => w.length >= 2 && !stopWords.contains(w.toLowerCase()))
        .toList();
    if (rawWords.isEmpty) return [];

    // ── Build expanded search-term set ────────────────────────────────────────
    final searchTerms = <String>{};          // exact substring terms
    final skelTerms   = <String>{};          // consonant skeletons for fuzzy

    for (final word in rawWords) {
      String wL = word.toLowerCase();

      // Layer 3: Urdu script → Roman transliteration
      if (RegExp(r'[\u0600-\u06FF]').hasMatch(wL)) {
        wL = _transliterateUrduToRoman(wL).toLowerCase().trim();
      }
      if (wL.length < 2) continue;

      searchTerms.add(wL);

      // Layer 1 — Direct synonym lookup
      final direct = _productSynonyms[wL];
      if (direct != null) searchTerms.addAll(direct);

      // Layer 1 — Reverse synonym lookup (user says "rice" → also add "chawal")
      for (final entry in _productSynonyms.entries) {
        if (entry.value.contains(wL) ||
            (wL.length >= 4 && entry.value.any((v) => v.contains(wL) || wL.contains(v)))) {
          searchTerms.add(entry.key);
          searchTerms.addAll(entry.value);
        }
      }

      // Layer 1 — Partial key match ("chawalon" contains key "chawal")
      for (final entry in _productSynonyms.entries) {
        if (entry.key.length >= 4 &&
            (wL.contains(entry.key) || entry.key.contains(wL))) {
          searchTerms.addAll(entry.value);
          searchTerms.add(entry.key);
        }
      }

      // Layer 2 — Phonetic skeleton for same-language fuzzy matching
      final norm = _normalizePhonetic(wL);
      if (norm.length >= 2) {
        searchTerms.add(norm);
        final sk = _consonantSkeleton(norm);
        if (sk.length >= 3) skelTerms.add(sk); // min 3 consonants avoids over-matching
      }
    }

    final seen    = <String>{};
    final results = <DemandItemModel>[];

    // Pre-compute item forms once (avoid recomputing per search term)
    final itemForms = <DemandItemModel, ({String nameL, String normName, String skelName, String barcodeL})>{};
    final urduRe = RegExp(r'[\u0600-\u06FF]');
    for (final item in allItems) {
      final raw = urduRe.hasMatch(item.name)
          ? _transliterateUrduToRoman(item.name).toLowerCase()
          : item.name.toLowerCase();
      final nm  = _normalizePhonetic(raw);
      final sk  = _consonantSkeleton(nm);
      itemForms[item] = (nameL: raw, normName: nm, skelName: sk, barcodeL: item.barcode.toLowerCase());
    }

    // ── Layer 1+3: exact / substring match ────────────────────────────────────
    for (final term in searchTerms) {
      if (term.length < 2) continue;
      for (final item in allItems) {
        if (seen.contains(item.id)) continue;
        final f = itemForms[item]!;
        if (f.nameL.contains(term) ||
            f.barcodeL.contains(term) ||
            (term.length >= 4 && term.contains(f.nameL))) {
          seen.add(item.id);
          results.add(item);
        }
      }
    }

    // ── Layer 2: phonetic skeleton match for items not yet found ──────────────
    if (skelTerms.isNotEmpty) {
      for (final item in allItems) {
        if (seen.contains(item.id)) continue;
        final f = itemForms[item]!;
        if (f.skelName.length < 3) continue;
        for (final sk in skelTerms) {
          final longer  = sk.length > f.skelName.length ? sk.length : f.skelName.length;
          final shorter = sk.length < f.skelName.length ? sk.length : f.skelName.length;
          if (shorter < longer * 0.65) continue; // length-ratio guard
          final maxD = sk.length <= 4 ? 0 : 1;
          if (_levenshtein(sk, f.skelName) <= maxD) {
            seen.add(item.id);
            results.add(item);
            break;
          }
        }
      }
    }

    return results;
  }

  // ── Voice: request mic permission then initialize ──────────────────────────
  Future<void> _requestMicAndInit() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        _showSnack(
          'Microphone permission denied — please allow in Settings',
          isError: true,
        );
      }
      return;
    }
    await _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onError: (e) {
        if (mounted) {
          setState(() => _isListening = false);
          _micPulseController.stop();
        }
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) {
            setState(() {
              _isListening = false;
              _soundLevel = 0;
            });
            _micPulseController.stop();
            _micPulseController.reset();
          }
        }
      },
    );
    if (mounted) setState(() => _speechReady = available);
  }

  // ── Mic button tapped ──────────────────────────────────────────────────────
  Future<void> _onMicTapped() async {
    if (_isLoading) return;
    if (!_speechReady) {
      await _requestMicAndInit();
      if (!_speechReady) return;
    }
    await _toggleVoice();
  }

  Future<void> _toggleVoice() async {
    if (!_speechReady) {
      _showSnack('Microphone not available — please check your device mic',
          isError: true);
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() {
        _isListening = false;
        _soundLevel = 0;
      });
      _micPulseController.stop();
      _micPulseController.reset();
    } else {
      _suppressVoiceResults = false; // allow results for this new listen session
      setState(() {
        _isListening = true;
        _soundLevel = 0;
      });
      _micPulseController.repeat(reverse: true);

      await _speech.listen(
        localeId: _voiceLocale,
        onResult: _onVoiceResult,
        onSoundLevelChange: (level) {
          if (mounted) setState(() => _soundLevel = level.clamp(0, 10));
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        listenOptions: SpeechListenOptions(cancelOnError: false),
      );
    }
  }

  // Detect voice locale from text — checks for Urdu/Arabic script presence
  // then Hindi script, then falls back to English. Works for any mixed text.
  static String _detectLocaleFromText(String text) {
    // Urdu/Arabic script (0600–06FF covers all Urdu chars)
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(text)) return 'ur_PK';
    // Devanagari (Hindi/Marathi)
    if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return 'hi_IN';
    // Default: English
    return 'en_US';
  }

  // FIX: Only fill text field — user must tap Send to send
  // AUTO-DETECT: After final result, auto-switch locale based on detected script
  void _onVoiceResult(SpeechRecognitionResult result) {
    // Issue 1 fix: suppress results that fire after _sendMessage calls stop()
    if (_suppressVoiceResults) return;
    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;
    setState(() {
      _controller.text = words;
      _controller.selection =
          TextSelection.fromPosition(TextPosition(offset: words.length));
    });
    if (result.finalResult) {
      if (mounted) {
        // Auto-detect language from recognized text and update locale for next session
        final detectedLocale = _detectLocaleFromText(words);
        final changed = detectedLocale != _voiceLocale;
        setState(() {
          _isListening = false;
          _soundLevel = 0;
          if (changed) _voiceLocale = detectedLocale;
        });
        _micPulseController.stop();
        _micPulseController.reset();
        // Show brief notification when locale auto-switched
        if (changed) {
          final langName = detectedLocale == 'ur_PK'
              ? 'اردو (Urdu)'
              : detectedLocale == 'hi_IN'
                  ? 'Hindi'
                  : 'English';
          _showSnack('Voice language auto-switched to $langName');
        }
      }
    }
  }

  void _showLocalePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LocalePickerSheet(
        current: _voiceLocale,
        onPick: (locale) {
          setState(() => _voiceLocale = locale);
          Navigator.pop(context);
        },
      ),
    );
  }

  // ── Contacts ───────────────────────────────────────────────────────────────
  Future<void> _tryLoadContacts() async {
    if (_contactsSvc.isLoaded || _contactsSvc.permissionDenied) return;
    setState(() => _contactsLoading = true);
    await _contactsSvc.loadContacts();
    if (mounted) setState(() => _contactsLoading = false);
  }

  Future<void> _requestContacts() async {
    setState(() => _contactsLoading = true);
    _contactsSvc.reset();
    final granted = await _contactsSvc.loadContacts();
    if (!mounted) return;
    setState(() => _contactsLoading = false);
    _showSnack(
      granted
          ? '✅ ${_contactsSvc.contacts.length} contacts synced'
          : '❌ Contacts permission denied — please allow in Settings',
      isError: !granted,
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _typingAnimController.dispose();
    _micPulseController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      margin: const EdgeInsets.all(12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Contact resolution ─────────────────────────────────────────────────────
  //
  // DISAMBIGUATION: If the message matches an item-query pattern AND does NOT
  // contain a definitive WhatsApp/send keyword, treat it as an item query even
  // if a loose communication word is present (e.g. "message" in "total message").
  // This prevents "chawal search karo" from triggering contact lookup.
  Future<String?> _resolveContactsIfNeeded(String text) async {
    if (!_waIntentRegex.hasMatch(text)) return text;

    // If the message has strong item-query signals (status, stock, hai, search…)
    // AND no definitive WhatsApp word (Roman or Urdu script), skip entirely.
    final hasItemIntent = _itemQueryRegex.hasMatch(text);
    final hasDefiniteWa = _definiteWaRegex.hasMatch(text);
    if (hasItemIntent && !hasDefiniteWa) return text;

    final candidates = _extractNameCandidates(text);
    if (candidates.isEmpty) return text;

    // ── Gather matches from phone contacts ─────────────────────────────────
    final seen = <String>{};
    final allMatches = <PhoneContact>[];
    String? primaryName;

    if (_contactsSvc.isLoaded) {
      for (final name in candidates) {
        final hits = _smartFindContacts(name);
        if (hits.isNotEmpty && primaryName == null) primaryName = name;
        for (final c in hits) {
          if (!seen.contains(c.phone)) {
            seen.add(c.phone);
            allMatches.add(c);
          }
        }
      }
    }

    // ── Also search app data: customers + suppliers ─────────────────────────
    for (final c in _findContactsInAppData(candidates)) {
      if (primaryName == null) primaryName = candidates.first;
      if (!seen.contains(c.phone)) {
        seen.add(c.phone);
        allMatches.add(c);
      }
    }

    if (allMatches.isEmpty) return text;
    if (allMatches.length == 1) {
      return '$text\n\n[Contact found: ${allMatches[0].name} → ${allMatches[0].phone}]';
    }
    final selected = await _showContactPickerDialog(
        primaryName ?? candidates.first, allMatches);
    if (selected == null) return null;
    return '$text\n\n[User selected contact: ${selected.name} → ${selected.phone}]';
  }

  Future<PhoneContact?> _showContactPickerDialog(
      String searchName, List<PhoneContact> contacts) {
    return showModalBottomSheet<PhoneContact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ContactPickerSheet(
        searchName: searchName,
        contacts: contacts,
        onSelected: (c) => Navigator.pop(ctx, c),
        onCancel: () => Navigator.pop(ctx, null),
      ),
    );
  }

  // ── Send message ──────────────────────────────────────────────────────────
  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;

    // Capture providers BEFORE any await — safe from BuildContext async gaps
    final demandProv  = context.read<DemandProvider>();
    final custProv    = context.read<CustomerProvider>();
    final suppProv    = context.read<SupplierProvider>();
    final udhaarProv  = context.read<UdhaarProvider>();
    final catProv     = context.read<CategoryProvider>();

    if (_isListening) {
      // Issue 1 fix: set flag BEFORE stop() so the final onResult callback
      // that speech_to_text fires after stop() is ignored.
      _suppressVoiceResults = true;
      await _speech.stop();
      setState(() {
        _isListening = false;
        _soundLevel = 0;
      });
      _micPulseController.stop();
      _micPulseController.reset();
    }

    _controller.clear();

    final resolved = await _resolveContactsIfNeeded(trimmed);
    if (resolved == null) return;

    // Inject local demand-item search results so the AI always has accurate
    // item data even beyond the 100-item backend limit.
    // The DemandProvider holds ALL items via Firestore real-time stream.
    String resolvedWithItems = resolved;
    if (_itemQueryRegex.hasMatch(trimmed)) {
      final allItems = demandProv.allItems;
      final totalCount = allItems.length;
      final itemMatches = _searchLocalItems(allItems, trimmed);
      if (itemMatches.isNotEmpty) {
        final itemContext = itemMatches
            .map((item) =>
                '${item.name}: status=${item.status}'
                '${item.quantity.isNotEmpty ? ", qty=${item.quantity}" : ""}')
            .join('\n');
        resolvedWithItems =
            '$resolved\n\n'
            '[App has $totalCount total demand items. '
            'Local search results for this query:\n$itemContext\n'
            'Use these results to answer — do NOT say item is not found if it appears above.]';
      } else if (totalCount > 0) {
        // No matches found — tell AI how many items exist so it can give accurate answer
        resolvedWithItems =
            '$resolved\n\n'
            '[App has $totalCount total demand items. '
            'No items matched this specific search query in local data.]';
      }
    }

    // ── Inject live store stats so AI always has current counts ─────────────
    // This runs on EVERY message (cheap — just reads provider values in memory).
    try {
      final totalDemand   = demandProv.allItems.length;
      final pendingCount  = demandProv.allItems.where((i) => i.status == 'pending').length;
      final urgentCount   = demandProv.allItems.where((i) => i.status == 'urgent').length;
      final availCount    = demandProv.allItems.where((i) => i.status == 'available').length;
      final deferredCount = demandProv.allItems.where((i) => i.status == 'deferred').length;
      final custCount     = custProv.all.length;
      final suppCount     = suppProv.all.length;
      final catCount      = catProv.categories.length;

      final liveStats =
          '[LIVE STORE STATS — use these for any count/total queries:\n'
          'Demand items: $totalDemand total '
          '(Pending=$pendingCount, Urgent=$urgentCount, Available=$availCount, Deferred=$deferredCount)\n'
          'Customers: $custCount | Suppliers: $suppCount | Categories: $catCount\n'
          'Udhaar: ${udhaarProv.pendingCount} pending entries, '
          'total given = Rs ${udhaarProv.totalGiven.toStringAsFixed(0)}, '
          'total received = Rs ${udhaarProv.totalReceived.toStringAsFixed(0)}, '
          'net balance = Rs ${udhaarProv.netBalance.toStringAsFixed(0)}]';

      resolvedWithItems = '$resolvedWithItems\n\n$liveStats';
    } catch (_) {}

    // Extract only the few contacts matching this message's query.
    // Client-side resolution already handles known names (they're in the message text).
    // We also pass relevant contacts as a fallback for server-side resolution.
    // Max 10 contacts — payload stays tiny regardless of total contact count.
    final relevantContacts = _getRelevantContacts(trimmed);

    final userDisplayMsg = AiMessage(role: 'user', content: trimmed);
    final userApiMsg = AiMessage(role: 'user', content: resolvedWithItems);

    setState(() {
      _svc.displayMessages.add(userDisplayMsg);
      _svc.apiMessages.add(userApiMsg);
      _isLoading = true;
    });
    _scrollToBottom();

    final result = await _svc.chat(
      List.from(_svc.apiMessages),
      relevantContacts: relevantContacts,
    );
    if (!mounted) return;

    // For displayMessages: keep the full reply (with ✅/❌ action result suffix)
    // For apiMessages: strip the action result lines so DeepSeek doesn't see
    // "✅ WhatsApp bhej diya gaya" in history and skip action JSON next time.
    final cleanedForApi = result.reply
        .replaceAll(RegExp(r'\n\n[✅❌🔄][^\n]*'), '')
        .trim();
    final assistantDisplayMsg =
        AiMessage(role: 'assistant', content: result.reply);
    final assistantApiMsg =
        AiMessage(role: 'assistant', content: cleanedForApi);
    setState(() {
      _isLoading = false;
      _svc.displayMessages.add(assistantDisplayMsg);
      _svc.apiMessages.add(assistantApiMsg);
    });
    _scrollToBottom();

    if (result.actionResult != null && mounted) {
      final ar = result.actionResult!;
      final phone = ar.raw['number']?.toString() ??
          ar.raw['phone']?.toString() ??
          ar.raw['phoneNumber']?.toString() ??
          '';
      final originalMsg = ar.raw['originalMessage']?.toString() ?? '';

      // Store for retry and update persistent retry state
      if (ar.isWhatsApp) {
        _lastWaPhone = phone;
        _lastWaMessage = originalMsg;
        setState(() => _lastWaFailed = !ar.success);
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          Icon(
            ar.success
                ? Icons.check_circle_outline
                : Icons.error_outline,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(ar.message,
                  style: const TextStyle(fontSize: 13))),
        ]),
        backgroundColor:
            ar.success ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        margin: const EdgeInsets.all(12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  /// Directly retry a failed WhatsApp send without going through the AI.
  Future<void> _retryWhatsApp(String phone, String message) async {
    if (phone.isEmpty) return;
    // Fall back to stored message if current one is empty
    if (message.isEmpty && _lastWaMessage != null) {
      message = _lastWaMessage!;
    }
    if (message.isEmpty) {
      // Can't retry without the message — show error
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Message content not found — please try the WhatsApp command again.'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white),
        ),
        SizedBox(width: 10),
        Text('Retrying WhatsApp...'),
      ]),
      backgroundColor: Colors.orange.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 30),
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));

    final retryResult = await _svc.directSendWhatsApp(
        phone: phone, message: message);
    if (!mounted) return;

    setState(() => _lastWaFailed = !retryResult.success);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(
            retryResult.success
                ? Icons.check_circle_outline
                : Icons.error_outline,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(retryResult.message,
                  style: const TextStyle(fontSize: 13))),
        ]),
        backgroundColor: retryResult.success
            ? Colors.green.shade700
            : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        margin: const EdgeInsets.all(12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
  }

  void _confirmClearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
            'All chat history will be deleted and the AI will lose its conversation context.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _svc.clearHistory());
            },
            child: const Text('Clear',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // ── Message bubble ─────────────────────────────────────────────────────────
  Widget _buildMessage(AiMessage msg) {
    final isUser = msg.role == 'user';
    final displayText = isUser
        ? msg.content
            .replaceAll(
                RegExp(r'\n\n\[Contact found:.*?\]', dotAll: true), '')
            .replaceAll(
                RegExp(r'\n\n\[User selected contact:.*?\]', dotAll: true),
                '')
            .replaceAll(
                RegExp(r'\n\n\[App has \d+ total demand items\..*?\]',
                    dotAll: true),
                '')
            .trim()
        : msg.content;

    return Padding(
      padding: EdgeInsets.only(
          left: isUser ? 56 : 0, right: isUser ? 0 : 56, bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, Color(0xFFFF6659)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.smart_toy_rounded,
                  color: Colors.white, size: 17),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: displayText));
                // Clear any existing snackbar first so only ONE "copied" notification shows
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(
                    content: const Row(children: [
                      Icon(Icons.copy_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text('Message copied', style: TextStyle(fontSize: 13)),
                    ]),
                    backgroundColor: Colors.grey.shade800,
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: isUser
                    ? Text(
                        displayText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      )
                    : MarkdownBody(
                        data: _cleanMarkdown(displayText),
                        styleSheet: _markdownStyle(),
                        softLineBreak: true,
                        shrinkWrap: true,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _cleanMarkdown(String text) =>
      text.replaceAll(RegExp(r'\[OFFSET:\d+\]\n?'), '').trim();

  MarkdownStyleSheet _markdownStyle() {
    const base =
        TextStyle(color: AppColors.onSurface, fontSize: 14, height: 1.5);
    return MarkdownStyleSheet(
      p: base,
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      h1: base.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
      h2: base.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      h3: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      code: base.copyWith(
        fontFamily: 'monospace',
        fontSize: 13,
        backgroundColor: const Color(0xFFF0F0F0),
      ),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      blockquote: base.copyWith(color: Colors.grey.shade700),
      blockquoteDecoration: BoxDecoration(
        border:
            Border(left: BorderSide(color: AppColors.primary, width: 3)),
        color: Colors.red.shade50,
      ),
      listBullet: base,
      // Table styling — properly aligned and bordered
      tableHead: base.copyWith(fontWeight: FontWeight.w700, fontSize: 13),
      tableBody: base.copyWith(fontSize: 13),
      tableHeadAlign: TextAlign.center,
      tableBorder: TableBorder.all(
        color: const Color(0xFFDDDDDD),
        width: 1,
        style: BorderStyle.solid,
      ),
      tableColumnWidth: const FlexColumnWidth(),
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.primary, Color(0xFFFF6659)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Colors.white, size: 17),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: AnimatedBuilder(
              animation: _typingAnimController,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final phase =
                      ((_typingAnimController.value * 3) - i)
                          .clamp(0.0, 1.0);
                  final opacity =
                      (phase < 0.5 ? phase * 2 : (1 - phase) * 2)
                          .clamp(0.3, 1.0);
                  return Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 2),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: opacity),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _isListening ? 52 : 0,
      child: _isListening
          ? Container(
              color: AppColors.primary.withValues(alpha: 0.06),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                AnimatedBuilder(
                  animation: _micPulseController,
                  builder: (_, __) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (i) {
                      final h = 6.0 +
                          (_soundLevel * 2) *
                              (0.4 +
                                  0.6 *
                                      ((i % 2 == 0)
                                          ? _micPulseAnim.value
                                          : (2 - _micPulseAnim.value)));
                      return Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 2),
                        width: 4,
                        height: h.clamp(4.0, 24.0),
                        decoration: BoxDecoration(
                          color: AppColors.primary
                              .withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _controller.text.isEmpty
                            ? 'Listening...'
                            : _controller.text,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.onSurface,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _voiceLocale == 'ur_PK'
                            ? 'Urdu • Press Send to send'
                            : 'English • Press Send to send',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    await _speech.stop();
                    setState(() {
                      _isListening = false;
                      _soundLevel = 0;
                      _voiceLocale =
                          _voiceLocale == 'ur_PK' ? 'en_US' : 'ur_PK';
                    });
                    _micPulseController.stop();
                    _micPulseController.reset();
                    Future.delayed(
                        const Duration(milliseconds: 200),
                        _toggleVoice);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _voiceLocale == 'ur_PK' ? 'اردو' : 'EN',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ]),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildContactsChip() {
    if (_contactsLoading) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ActionChip(
          avatar: const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          label:
              const Text('Contacts...', style: TextStyle(fontSize: 11)),
          backgroundColor: Colors.grey.shade100,
          side: BorderSide(color: Colors.grey.shade300),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          visualDensity: VisualDensity.compact,
          onPressed: null,
        ),
      );
    }
    if (_contactsSvc.isLoaded) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ActionChip(
          avatar: const Icon(Icons.contacts_rounded,
              size: 14, color: Colors.green),
          label: Text('${_contactsSvc.contacts.length} contacts ✓',
              style:
                  const TextStyle(fontSize: 11, color: Colors.green)),
          backgroundColor: Colors.green.shade50,
          side: BorderSide(color: Colors.green.shade200),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          visualDensity: VisualDensity.compact,
          onPressed: _requestContacts,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: const Icon(Icons.contacts_rounded,
            size: 14, color: Colors.orange),
        label: const Text('Sync Contacts',
            style: TextStyle(fontSize: 11, color: Colors.orange)),
        backgroundColor: Colors.orange.shade50,
        side: BorderSide(color: Colors.orange.shade200),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        visualDensity: VisualDensity.compact,
        onPressed: _requestContacts,
      ),
    );
  }

  Widget _buildMicButton() {
    return AnimatedBuilder(
      animation: _micPulseAnim,
      builder: (_, child) => Transform.scale(
        scale: _isListening ? _micPulseAnim.value : 1.0,
        child: child,
      ),
      child: GestureDetector(
        onTap: _isLoading ? null : _onMicTapped,
        onLongPress: _isLoading ? null : _showLocalePicker,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _isListening
                ? AppColors.primary
                : _isLoading
                    ? Colors.grey.shade200
                    : AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            boxShadow: _isListening
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
          child: Icon(
            _isListening ? Icons.stop_rounded : Icons.mic_rounded,
            color: _isListening
                ? Colors.white
                : _isLoading
                    ? Colors.grey.shade400
                    : AppColors.primary,
            size: 20,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFFFF6659)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Colors.white, size: 21),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('AI Assistant',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              Row(children: [
                Icon(Icons.lock_rounded,
                    size: 10, color: AppColors.primary),
                SizedBox(width: 3),
                Text('Admin Only',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500)),
              ]),
            ],
          ),
        ]),
        actions: [
          IconButton(
            icon: Text(
              _voiceLocale == 'ur_PK' ? 'اردو' : 'EN',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary),
            ),
            tooltip: 'Voice language toggle',
            onPressed: _showLocalePicker,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear chat',
            onPressed: _confirmClearChat,
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildContactsChip(),
                ..._quickPrompts.map((p) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(p,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                        onPressed: _isLoading
                            ? null
                            : () => _sendMessage(p),
                        backgroundColor: Colors.red.shade50,
                        side: BorderSide(
                            color: Colors.red.shade200),
                        labelStyle:
                            TextStyle(color: Colors.red.shade700),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    )),
              ],
            ),
          ),
        ),
        Container(height: 1, color: Colors.grey.shade200),

        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            itemCount: _svc.displayMessages.length +
                (_isLoading ? 1 : 0),
            itemBuilder: (_, i) {
              if (_isLoading && i == _svc.displayMessages.length) {
                return _buildTypingIndicator();
              }
              return _buildMessage(_svc.displayMessages[i]);
            },
          ),
        ),

        ClipRect(child: _buildVoiceBar()),

        // ── Persistent WhatsApp retry button ───────────────────────────
        if (_lastWaFailed && _lastWaPhone != null)
          Container(
            color: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.error_outline_rounded,
                        color: Colors.red.shade700, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('WhatsApp failed',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.red.shade700)),
                        Text('to: $_lastWaPhone',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.red.shade400),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _retryWhatsApp(
                        _lastWaPhone!, _lastWaMessage ?? ''),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Retry',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _lastWaFailed = false),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: Colors.red.shade400),
                  ),
                ],
              ),
            ),
          ),

        Container(height: 1, color: Colors.grey.shade200),

        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildMicButton(),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_isLoading,
                    maxLines: 5,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _isListening
                          ? 'Listening... (press Send to send)'
                          : 'Type a command or question...',
                      hintStyle: TextStyle(
                        color: _isListening
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: _isListening
                          ? AppColors.primary.withValues(alpha: 0.05)
                          : const Color(0xFFF5F6FA),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: _isListening
                              ? const BorderSide(
                                  color: AppColors.primary, width: 1.5)
                              : BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: _isListening
                              ? const BorderSide(
                                  color: AppColors.primary, width: 1.5)
                              : BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: _isLoading
                      ? Colors.grey.shade300
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    onTap: _isLoading
                        ? null
                        : () => _sendMessage(_controller.text),
                    borderRadius: BorderRadius.circular(24),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
        ),
    );
  }
}

// ── Language Picker Sheet ─────────────────────────────────────────────────────
class _LocalePickerSheet extends StatelessWidget {
  final String current;
  final void Function(String) onPick;

  const _LocalePickerSheet(
      {required this.current, required this.onPick});

  static const _locales = [
    ('ur_PK', 'اردو', 'Urdu — Pakistan', '🇵🇰'),
    ('en_US', 'EN', 'English', '🇺🇸'),
    ('en_IN', 'EN-IN', 'English — India', '🇮🇳'),
    ('hi_IN', 'हिं', 'Hindi', '🇮🇳'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Row(children: [
            Icon(Icons.language_rounded,
                color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text('Select Voice Language',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 12),
          ..._locales.map((l) {
            final isSelected = current == l.$1;
            return ListTile(
              leading:
                  Text(l.$4, style: const TextStyle(fontSize: 22)),
              title: Text(l.$3,
                  style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.onSurface)),
              subtitle: Text(l.$2,
                  style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : Colors.grey)),
              trailing: isSelected
                  ? const Icon(Icons.check_circle_rounded,
                      color: AppColors.primary, size: 20)
                  : null,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              tileColor: isSelected
                  ? AppColors.primary.withValues(alpha: 0.06)
                  : null,
              onTap: () => onPick(l.$1),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            );
          }),
        ],
      ),
    );
  }
}

// ── Contact Picker Bottom Sheet ───────────────────────────────────────────────
class _ContactPickerSheet extends StatefulWidget {
  final String searchName;
  final List<PhoneContact> contacts;
  final void Function(PhoneContact) onSelected;
  final VoidCallback onCancel;

  const _ContactPickerSheet({
    required this.searchName,
    required this.contacts,
    required this.onSelected,
    required this.onCancel,
  });

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  String _filter = '';

  List<PhoneContact> get _filtered {
    if (_filter.trim().isEmpty) return widget.contacts;
    final q = _filter.toLowerCase();
    return widget.contacts
        .where((c) =>
            c.name.toLowerCase().contains(q) || c.phone.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.75;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.contacts_rounded,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Multiple contacts found for "${widget.searchName}"',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      Text('Which contact do you want to select?',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: widget.onCancel,
                  iconSize: 20,
                ),
              ],
            ),
          ),
          if (widget.contacts.length > 5)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 4),
              child: TextField(
                onChanged: (v) => setState(() => _filter = v),
                decoration: InputDecoration(
                  hintText: 'Search contacts...',
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon:
                      const Icon(Icons.search_rounded, size: 18),
                  filled: true,
                  fillColor: const Color(0xFFF5F6FA),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  isDense: true,
                ),
              ),
            ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _filtered.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (ctx, i) {
                final c = _filtered[i];
                final initial =
                    c.name.isNotEmpty ? c.name[0].toUpperCase() : '?';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        AppColors.primary.withValues(alpha: 0.15),
                    radius: 20,
                    child: Text(initial,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        )),
                  ),
                  title: Text(c.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(c.phone,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Select',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  onTap: () => widget.onSelected(c),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onCancel,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.grey)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
