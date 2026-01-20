import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:convert';
import 'dart:math';

void main() {
  runApp(const SecureVaultApp());
}

class SecureVaultApp extends StatelessWidget {
  const SecureVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecureVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
      ),
      home: const MasterPasswordScreen(),
    );
  }
}

// ============ ŞİFRELEME SERVİSİ ============
class EncryptionService {
  static const _keyStorageKey = 'encryption_key';
  static const _ivStorageKey = 'encryption_iv';
  static final _storage = FlutterSecureStorage();

  static encrypt.Key? _key;
  static encrypt.IV? _iv;

  static Future<void> initialize() async {
    String? keyString = await _storage.read(key: _keyStorageKey);
    String? ivString = await _storage.read(key: _ivStorageKey);

    if (keyString == null || ivString == null) {
      // İlk kurulum - yeni key ve IV oluştur
      final random = Random.secure();
      final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
      final ivBytes = List<int>.generate(16, (_) => random.nextInt(256));

      keyString = base64.encode(keyBytes);
      ivString = base64.encode(ivBytes);

      await _storage.write(key: _keyStorageKey, value: keyString);
      await _storage.write(key: _ivStorageKey, value: ivString);
    }

    _key = encrypt.Key.fromBase64(keyString);
    _iv = encrypt.IV.fromBase64(ivString);
  }

  static String encryptText(String plainText) {
    if (_key == null || _iv == null) return plainText;
    final encrypter = encrypt.Encrypter(encrypt.AES(_key!));
    final encrypted = encrypter.encrypt(plainText, iv: _iv);
    return encrypted.base64;
  }

  static String decryptText(String encryptedText) {
    if (_key == null || _iv == null) return encryptedText;
    try {
      final encrypter = encrypt.Encrypter(encrypt.AES(_key!));
      final decrypted = encrypter.decrypt64(encryptedText, iv: _iv);
      return decrypted;
    } catch (e) {
      return encryptedText;
    }
  }
}

// ============ VERİ SAKLAMA SERVİSİ ============
class StorageService {
  static const _storage = FlutterSecureStorage();
  static const _passwordsKey = 'saved_passwords';
  static const _masterPasswordKey = 'master_password';

  // Master password kaydet
  static Future<void> setMasterPassword(String password) async {
    final encrypted = EncryptionService.encryptText(password);
    await _storage.write(key: _masterPasswordKey, value: encrypted);
  }

  // Master password kontrol
  static Future<String?> getMasterPassword() async {
    final encrypted = await _storage.read(key: _masterPasswordKey);
    if (encrypted == null) return null;
    return EncryptionService.decryptText(encrypted);
  }

  // Şifreleri kaydet
  static Future<void> savePasswords(List<Map<String, String>> passwords) async {
    // Her şifreyi encrypt et
    final encryptedList = passwords.map((p) {
      return {
        'title': p['title']!,
        'username': p['username']!,
        'password': EncryptionService.encryptText(p['password']!),
        'category': p['category']!,
      };
    }).toList();

    final jsonString = jsonEncode(encryptedList);
    await _storage.write(key: _passwordsKey, value: jsonString);
  }

  // Şifreleri yükle
  static Future<List<Map<String, String>>> loadPasswords() async {
    final jsonString = await _storage.read(key: _passwordsKey);
    if (jsonString == null) return [];

    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded.map((item) {
      return {
        'title': item['title'] as String,
        'username': item['username'] as String,
        'password': EncryptionService.decryptText(item['password'] as String),
        'category': item['category'] as String,
      };
    }).toList();
  }
}

// ============ KATEGORİ BİLGİLERİ ============
class Category {
  static const Map<String, IconData> icons = {
    'Sosyal Medya': Icons.people,
    'Banka': Icons.account_balance,
    'E-posta': Icons.email,
    'Alışveriş': Icons.shopping_cart,
    'Oyun': Icons.games,
    'Diğer': Icons.folder,
  };

  static const Map<String, Color> colors = {
    'Sosyal Medya': Colors.pink,
    'Banka': Colors.green,
    'E-posta': Colors.orange,
    'Alışveriş': Colors.purple,
    'Oyun': Colors.red,
    'Diğer': Colors.grey,
  };
}

// ============ ŞİFRE GÜÇ HESAPLAYICI ============
class PasswordStrength {
  static Map<String, dynamic> calculate(String password) {
    int score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (password.length >= 16) score++;
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[a-z]'))) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) score++;

    String label;
    Color color;
    if (score <= 2) {
      label = 'Zayıf';
      color = Colors.red;
    } else if (score <= 4) {
      label = 'Orta';
      color = Colors.orange;
    } else if (score <= 5) {
      label = 'Güçlü';
      color = Colors.lightGreen;
    } else {
      label = 'Çok Güçlü';
      color = Colors.green;
    }

    return {'score': score, 'label': label, 'color': color, 'percentage': score / 7};
  }
}

// ============ MASTER PASSWORD EKRANI ============
class MasterPasswordScreen extends StatefulWidget {
  const MasterPasswordScreen({super.key});

  @override
  State<MasterPasswordScreen> createState() => _MasterPasswordScreenState();
}

class _MasterPasswordScreenState extends State<MasterPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = true;
  bool _isFirstTime = false;
  bool _isConfirming = false;
  String _firstPassword = '';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await EncryptionService.initialize();
    final savedPassword = await StorageService.getMasterPassword();
    setState(() {
      _isFirstTime = savedPassword == null;
      _isLoading = false;
    });
  }

  Future<void> _handleSubmit() async {
    final input = _passwordController.text;
    if (input.isEmpty) {
      _showError('Şifre boş olamaz!');
      return;
    }

    if (_isFirstTime) {
      if (!_isConfirming) {
        // İlk giriş
        if (input.length < 4) {
          _showError('Şifre en az 4 karakter olmalı!');
          return;
        }
        setState(() {
          _firstPassword = input;
          _isConfirming = true;
          _passwordController.clear();
        });
      } else {
        // Onay girişi
        if (input == _firstPassword) {
          await StorageService.setMasterPassword(input);
          _goToHome();
        } else {
          _showError('Şifreler eşleşmiyor!');
          setState(() {
            _isConfirming = false;
            _firstPassword = '';
            _passwordController.clear();
          });
        }
      }
    } else {
      // Normal giriş
      final savedPassword = await StorageService.getMasterPassword();
      if (input == savedPassword) {
        _goToHome();
      } else {
        _showError('Yanlış şifre!');
        _passwordController.clear();
      }
    }
  }

  void _goToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    String title;
    String subtitle;
    String buttonText;

    if (_isFirstTime) {
      if (_isConfirming) {
        title = 'Şifreyi Onayla';
        subtitle = 'Ana şifrenizi tekrar girin';
        buttonText = 'Onayla';
      } else {
        title = 'Hoş Geldiniz!';
        subtitle = 'Yeni ana şifrenizi belirleyin';
        buttonText = 'Devam';
      }
    } else {
      title = 'SecureVault';
      subtitle = 'Ana şifrenizi girin';
      buttonText = 'Kilidi Aç';
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isFirstTime ? Icons.add_moderator : Icons.shield,
                  size: 60,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 24),
              Text(title,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              Text(subtitle, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 48),
              TextField(
                controller: _passwordController,
                obscureText: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: InputDecoration(
                  hintText: '••••',
                  hintStyle: const TextStyle(letterSpacing: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1A),
                ),
                onSubmitted: (_) => _handleSubmit(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(buttonText, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============ ANA EKRAN ============
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, String>> passwords = [];
  String _searchQuery = '';
  String _selectedCategory = 'Tümü';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPasswords();
  }

  Future<void> _loadPasswords() async {
    final loaded = await StorageService.loadPasswords();
    setState(() {
      passwords = loaded;
      _isLoading = false;
    });
  }

  Future<void> _savePasswords() async {
    await StorageService.savePasswords(passwords);
  }

  List<Map<String, String>> get filteredPasswords {
    return passwords.where((p) {
      final matchesSearch = p['title']!.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p['username']!.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCategory = _selectedCategory == 'Tümü' || p['category'] == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  void _addPassword(Map<String, String> newPassword) {
    setState(() => passwords.add(newPassword));
    _savePasswords();
  }

  void _deletePassword(int index) {
    final actualIndex = passwords.indexOf(filteredPasswords[index]);
    setState(() => passwords.removeAt(actualIndex));
    _savePasswords();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Şifre kopyalandı!'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SecureVault', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const MasterPasswordScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Şifre ara...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
              ),
            ),
          ),
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildCategoryChip('Tümü', Icons.all_inclusive, Colors.blue),
                ...Category.icons.entries.map((e) =>
                    _buildCategoryChip(e.key, e.value, Category.colors[e.key]!)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filteredPasswords.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_open, size: 60, color: Colors.grey[700]),
                        const SizedBox(height: 16),
                        Text(
                          passwords.isEmpty ? 'Henüz şifre eklenmedi' : 'Sonuç bulunamadı',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredPasswords.length,
                    itemBuilder: (context, index) {
                      final item = filteredPasswords[index];
                      final category = item['category'] ?? 'Diğer';
                      final strength = PasswordStrength.calculate(item['password']!);

                      return Card(
                        color: const Color(0xFF1A1A1A),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _showPasswordDetail(item, index),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Category.colors[category]!.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Category.icons[category], color: Category.colors[category]),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      const SizedBox(height: 4),
                                      Text(item['username']!, style: TextStyle(color: Colors.grey[500])),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Container(
                                            width: 60,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(2),
                                              color: Colors.grey[800],
                                            ),
                                            child: FractionallySizedBox(
                                              alignment: Alignment.centerLeft,
                                              widthFactor: strength['percentage'],
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(2),
                                                  color: strength['color'],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(strength['label'], style: TextStyle(fontSize: 12, color: strength['color'])),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, color: Colors.blue),
                                  onPressed: () => _copyToClipboard(item['password']!),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddPasswordScreen()),
          );
          if (result != null) _addPassword(result);
        },
        backgroundColor: Colors.blue,
        icon: const Icon(Icons.add),
        label: const Text('Yeni Şifre'),
      ),
    );
  }

  Widget _buildCategoryChip(String label, IconData icon, Color color) {
    final isSelected = _selectedCategory == label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        selected: isSelected,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : color),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
        onSelected: (_) => setState(() => _selectedCategory = label),
        backgroundColor: const Color(0xFF1A1A1A),
        selectedColor: color,
        checkmarkColor: Colors.white,
      ),
    );
  }

  void _showPasswordDetail(Map<String, String> item, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Category.colors[item['category']]!.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Category.icons[item['category']], color: Category.colors[item['category']], size: 32),
                ),
                const SizedBox(width: 16),
                Text(item['title']!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 24),
            _buildDetailRow('Kullanıcı Adı', item['username']!),
            const SizedBox(height: 16),
            _buildDetailRow('Şifre', item['password']!, isPassword: true),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _copyToClipboard(item['password']!);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Kopyala'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _deletePassword(index);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete),
                    label: const Text('Sil'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isPassword = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                isPassword ? '••••••••••••' : value,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () => _copyToClipboard(value),
            ),
          ],
        ),
      ],
    );
  }
}

// ============ YENİ ŞİFRE EKLEME EKRANI ============
class AddPasswordScreen extends StatefulWidget {
  const AddPasswordScreen({super.key});

  @override
  State<AddPasswordScreen> createState() => _AddPasswordScreenState();
}

class _AddPasswordScreenState extends State<AddPasswordScreen> {
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String _selectedCategory = 'Diğer';
  Map<String, dynamic> _strength = {'score': 0, 'label': 'Zayıf', 'color': Colors.red, 'percentage': 0.0};

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_updateStrength);
  }

  void _updateStrength() {
    setState(() {
      _strength = PasswordStrength.calculate(_passwordController.text);
    });
  }

  void _generatePassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()_+-=';
    final random = Random.secure();
    final password = List.generate(20, (_) => chars[random.nextInt(chars.length)]).join();
    _passwordController.text = password;
  }

  void _savePassword() {
    if (_titleController.text.isEmpty || _usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tüm alanları doldurun!')),
      );
      return;
    }
    Navigator.pop(context, {
      'title': _titleController.text,
      'username': _usernameController.text,
      'password': _passwordController.text,
      'category': _selectedCategory,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Şifre'),
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Kategori', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: Category.icons.entries.map((e) {
                final isSelected = _selectedCategory == e.key;
                return ChoiceChip(
                  selected: isSelected,
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(e.value, size: 18, color: isSelected ? Colors.white : Category.colors[e.key]),
                      const SizedBox(width: 4),
                      Text(e.key),
                    ],
                  ),
                  onSelected: (_) => setState(() => _selectedCategory = e.key),
                  backgroundColor: const Color(0xFF1A1A1A),
                  selectedColor: Category.colors[e.key],
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Başlık',
                hintText: 'örn: Gmail, Instagram',
                prefixIcon: const Icon(Icons.title),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Kullanıcı Adı / E-posta',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Şifre',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    IconButton(
                      icon: const Icon(Icons.auto_awesome, color: Colors.amber),
                      onPressed: _generatePassword,
                      tooltip: 'Güçlü Şifre Oluştur',
                    ),
                  ],
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _strength['percentage'],
                      backgroundColor: Colors.grey[800],
                      valueColor: AlwaysStoppedAnimation<Color>(_strength['color']),
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(_strength['label'], style: TextStyle(color: _strength['color'], fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _savePassword,
                icon: const Icon(Icons.save),
                label: const Text('Kaydet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.removeListener(_updateStrength);
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}