import 'package:flutter/material.dart';
import '../controllers/login_controller.dart';
import '../../services/storage_service.dart';
import '../../data/api/rest.dart';

class LoginScreen extends StatefulWidget {
  final ApiClient apiClient; // Added apiClient field

  const LoginScreen({super.key, required this.apiClient}); // Updated constructor

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final LoginController _controller;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController(); // For registration

  bool _isLogin = true; // To toggle between login and register
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Use the ApiClient passed via the widget
    final storageService = StorageService();
    _controller = LoginController(widget.apiClient, storageService); // Use widget.apiClient
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      bool success;
      if (_isLogin) {
        success = await _controller.login(
          _emailController.text,
          _passwordController.text,
        );
      } else {
        success = await _controller.register(
          _nicknameController.text,
          _emailController.text,
          _passwordController.text,
        );
      }

      setState(() {
        _isLoading = false;
      });

      if (success) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        setState(() {
          _errorMessage = _controller.errorMessage ?? "An unknown error occurred.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Login' : 'Register'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (!_isLogin)
                TextFormField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(labelText: 'Nickname'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your nickname';
                    }
                    return null;
                  },
                ),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password';
                  }
                  if (value.length < 6 && !_isLogin) { // Basic password length for registration
                     return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: _submit,
                  child: Text(_isLogin ? 'Login' : 'Register'),
                ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                    _errorMessage = null; // Clear error when switching modes
                    _formKey.currentState?.reset(); // Reset form fields
                  });
                },
                child: Text(
                    _isLogin ? 'Create an account' : 'Have an account? Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
