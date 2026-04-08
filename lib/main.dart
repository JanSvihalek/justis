import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

void main() => runApp(const JustisApp());

class JustisApp extends StatelessWidget {
  const JustisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Justis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
          color: Color(0xFFF1F3F4),
        ),
        appBarTheme: const AppBarTheme(centerTitle: true, backgroundColor: Colors.white, elevation: 0),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFF8F9FA),
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)), borderSide: BorderSide.none),
          prefixIconColor: Color(0xFF1A73E8),
        ),
      ),
      home: const SearchPage(),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  List<dynamic> _searchResults = [];
  Map<String, dynamic>? _selectedCompany;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeOutQuart);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openMap(String address) async {
    final query = Uri.encodeComponent(address);
    // Univerzální schéma pro Google Mapy
    final url = 'https://www.google.com/maps/search/?api=1&query=$query';
    await _launch(url);
  }

  Future<void> _startScanning() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => OCRScannerPage(camera: cameras.first)),
    );

    if (result != null && result is String) {
      setState(() {
        _searchController.text = result;
      });
      _handleSearch();
    }
  }

  String _translateLegalForm(dynamic code) {
    final String c = code.toString();
    switch (c) {
      case '112': return 's.r.o.';
      case '121': return 'a.s.';
      case '101': return 'OSVČ';
      case '706': return 'Spolek';
      default: return 'Právnická osoba';
    }
  }

  Future<void> _handleSearch() async {
    FocusScope.of(context).unfocus();
    String query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() { _isLoading = true; _errorMessage = null; _searchResults = []; _selectedCompany = null; });
    _animationController.reset();

    if (RegExp(r'^\d+$').hasMatch(query) && query.length <= 8) {
      await _fetchByIco(query.padLeft(8, '0'));
    } else {
      await _fetchByName(query);
    }
  }

  Future<void> _fetchByIco(String ico) async {
    try {
      final res = await http.get(Uri.parse('https://ares.gov.cz/ekonomicke-subjekty-v-be/rest/ekonomicke-subjekty/$ico'));
      if (res.statusCode == 200) {
        setState(() { _selectedCompany = json.decode(res.body); _searchResults = []; });
        _animationController.forward();
      } else {
        setState(() => _errorMessage = 'Subjekt nebyl nalezen.');
      }
    } catch (_) { setState(() => _errorMessage = 'Chyba sítě.'); }
    finally { setState(() => _isLoading = false); }
  }

  Future<void> _fetchByName(String name) async {
    try {
      final res = await http.post(
        Uri.parse('https://ares.gov.cz/ekonomicke-subjekty-v-be/rest/ekonomicke-subjekty/vyhledat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"obchodniJmeno": name, "pocet": 15}),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() => _searchResults = data['ekonomickeSubjekty'] ?? []);
      }
    } catch (_) { setState(() => _errorMessage = 'Chyba při vyhledávání.'); }
    finally { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(toolbarHeight: 90, title: _buildHeader()),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                labelText: 'IČO nebo název firmy', 
                prefixIcon: const Icon(Icons.search_rounded, size: 24),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.camera_alt_rounded),
                  onPressed: _startScanning,
                ),
              ),
              onSubmitted: (_) => _handleSearch(),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity, height: 58,
              child: FilledButton(
                onPressed: _isLoading ? null : _handleSearch,
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 2),
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('PROVĚŘIT SUBJEKT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.8)),
              ),
            ),
            if (_errorMessage != null) Padding(padding: const EdgeInsets.only(top: 25), child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent))),
            if (_searchResults.isNotEmpty && _selectedCompany == null)
              Padding(padding: const EdgeInsets.only(top: 20), child: Column(children: _searchResults.map((item) => _buildResultTile(item)).toList())),
            if (_selectedCompany != null)
              FadeTransition(opacity: _fadeAnimation, child: _buildCompanyCard()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF1A73E8).withOpacity(0.1), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.gavel_rounded, color: Color(0xFF1A73E8), size: 26)),
    const SizedBox(width: 14),
    ShaderMask(shaderCallback: (bounds) => const LinearGradient(colors: [Color(0xFF1A73E8), Color(0xFF673AB7)]).createShader(bounds), child: const Text('JUSTIS', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2.5, color: Colors.white))),
  ]);

  Widget _buildResultTile(dynamic item) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    color: const Color(0xFFF8F9FA),
    child: ListTile(
      title: Text(item['obchodniJmeno'], style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('IČO: ${item['ico']}'),
      onTap: () => _fetchByIco(item['ico']),
    ),
  );

  Widget _buildCompanyCard() {
    final data = _selectedCompany!;
    final address = data['sidlo']?['textovaAdresa'] ?? '';
    bool isUnreliable = data['priznakySubjektu']?['nespolehlivyPlatce'] == true;
    bool isVatPayer = data['dic'] != null;

    return Card(
      margin: const EdgeInsets.only(top: 25),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data['obchodniJmeno'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.2)),
            const SizedBox(height: 12),
            if (isVatPayer) _badge(isUnreliable ? "NESPOLEHLIVÝ PLÁTCE DPH" : "SPOLEHLIVÝ PLÁTCE DPH", isUnreliable ? Colors.orange : Colors.green),
            const SizedBox(height: 20),
            _row(Icons.fingerprint_rounded, 'IČO: ${data['ico']}'),
            if (data['dic'] != null) _row(Icons.receipt_long_outlined, 'DIČ: ${data['dic']}'),
            _row(Icons.account_balance_outlined, _translateLegalForm(data['pravniForma'])),
            _row(Icons.location_on_outlined, address),
            const Divider(height: 45, color: Color(0xFFDADCE0)),
            
            // --- POŘADÍ TLAČÍTEK ---
            _btn('SBÍRKA LISTIN (JUSTICE)', Icons.description_outlined, const Color(0xFF0F9D58), () => _launch('https://or.justice.cz/ias/ui/rejstrik-dotaz?dotaz=${data['ico']}')),
            _btn('HLEDAT NA WEBU', Icons.language_rounded, const Color(0xFF1A73E8), () => _launch('https://www.google.com/search?q=${Uri.encodeComponent(data['obchodniJmeno'])}')),
            _btn('UKÁZAT NA MAPĚ', Icons.map_rounded, Colors.orange, () => _openMap(address)),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.5))),
    child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
  );

  Widget _row(IconData icon, String text) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [Icon(icon, size: 18, color: const Color(0xFF5F6368)), const SizedBox(width: 12), Flexible(child: Text(text, style: const TextStyle(fontSize: 15)))]));

  Widget _btn(String label, IconData icon, Color col, VoidCallback tap) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: SizedBox(width: double.infinity, height: 54, child: FilledButton.tonalIcon(onPressed: tap, icon: Icon(icon, size: 22), label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)), style: FilledButton.styleFrom(backgroundColor: col.withOpacity(0.08), foregroundColor: col, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
  );

  Future<void> _launch(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nelze otevřít odkaz.')));
    }
  }
}

// --- STRÁNKA PRO OCR SKENOVÁNÍ ---
class OCRScannerPage extends StatefulWidget {
  final CameraDescription camera;
  const OCRScannerPage({super.key, required this.camera});
  @override
  State<OCRScannerPage> createState() => _OCRScannerPageState();
}

class _OCRScannerPageState extends State<OCRScannerPage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.high, enableAudio: false);
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _scanText() async {
    try {
      await _initializeControllerFuture;
      final image = await _controller.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      String foundText = "";
      RegExp icoRegex = RegExp(r'\d{8}');

      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          if (icoRegex.hasMatch(line.text)) {
            foundText = icoRegex.firstMatch(line.text)!.group(0)!;
            break;
          }
        }
      }

      if (foundText.isEmpty && recognizedText.text.isNotEmpty) {
        foundText = recognizedText.blocks.first.lines.first.text;
      }

      if (mounted) Navigator.pop(context, foundText);
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return Center(child: CameraPreview(_controller));
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            },
          ),
          Positioned(
            bottom: 60,
            left: 0, right: 0,
            child: Center(
              child: FloatingActionButton.large(
                onPressed: _scanText,
                backgroundColor: Colors.white,
                child: const Icon(Icons.camera_rounded, color: Color(0xFF1A73E8), size: 40),
              ),
            ),
          ),
          Positioned(top: 40, left: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context))),
        ],
      ),
    );
  }
}