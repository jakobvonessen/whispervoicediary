import 'secrets.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:dropbox_client/dropbox_client.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

const String dropbox_clientId = 'test-flutter-dropbox';

void main() {
  return runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: Home());
  }
}

class Home extends StatefulWidget {
  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String? accessToken;
  String? credentials;
  bool showInstruction = false;

  @override
  void initState() {
    super.initState();
    initDropbox();
  }

  FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  String filePath = "";
  String tempFileName = "";
  bool _isRecording = false;
  bool _isPaused = false;
  bool _hasRecorded = false;
  bool _isUploading = false;
  int _uploadProgress = 0;
  bool _hasUploaded = false;
  bool _isLinked = true;
  String _preUploadMessage = "Upload";
  String _recordingSeconds = "0";
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;


  void startTimer() {
    _stopwatch.reset();
    setState(() {
      _recordingSeconds = "0";
    });
    _stopwatch.start();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _recordingSeconds = _stopwatch.elapsed.inSeconds.toString();
      });
    });
  }
  void toggleTimer() {
    if (_stopwatch.isRunning) {
      _stopwatch.stop();
      _timer?.cancel();
    } else {
      _stopwatch.start();
      _timer = Timer.periodic(Duration(seconds: 1), (timer) {
        setState(() {
          _recordingSeconds = _stopwatch.elapsed.inSeconds.toString();
        });
      });
    }
  }

  void stopTimer() {
    _stopwatch.stop();
    _timer?.cancel();
  }

  void resetTimer() {
    _stopwatch.reset();
    setState(() {});
  }

  Future<String> getExternalPath() async {
    if (await Permission.storage.request().isGranted) {
      // Get the external storage directory
      final Directory? externalDir = (await getExternalStorageDirectory())?.parent;
      String newFolderName = "Whisperer";
      // Find existing or create a new directory
      final Directory newDirectory = Directory('${externalDir?.path}/$newFolderName');
      if (!await newDirectory.exists()) {
        await newDirectory.create(recursive: true);
      }
      return newDirectory.path;
    } else {
      throw Exception('Storage Permission not granted');
    }
  }

  Future startRecording() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
    await _recorder.openRecorder();

    var saveDir = await getExternalPath();
    tempFileName = DateFormat('yyyy-MM-dd-HH-mm-ss').format(DateTime.now());
    filePath = '${saveDir}/$tempFileName.aac';
    await _recorder.startRecorder(toFile: filePath);
    setState(() {
      _isRecording = true;
      _hasRecorded = false;
    });
    startTimer();
  }

  Future<void> toggleRecording() async {
    if (_recorder.isRecording) {
      await _recorder.pauseRecorder();
      setState(() {
        _isPaused = true;
      });
    } else if (_recorder.isPaused) {
      await _recorder.resumeRecorder();
      setState(() {
        _isPaused = false;
      });
    }
    toggleTimer();
  }

  Future stopRecording() async {
    await _recorder.stopRecorder();
    setState(() {
      _isRecording = false;
      _hasRecorded = true;
      _hasUploaded = false;
    });
    stopTimer();
  }

  Future uploadVoiceRecording() async {
    setState(() {
      _hasUploaded = false;
    });
    if (await checkAuthorized(true)) {
      try {
        final result = await Dropbox.upload(
          filePath,
          '/${tempFileName}.aac',
          (uploaded, total) {
            setState(() {
              _isUploading = true;
              _uploadProgress = ((uploaded / total) * 100).round();
            });
          },
        );
        setState(() {
          _isLinked = true;
        });
      } catch (e) {
        setState(() {
          _isLinked = false;
        });
      }
      setState(() {
        _isUploading = false;
      });
      if (_isLinked && await fileExistsInDropbox()) {
        setState(() {
          _hasUploaded = true;
          _preUploadMessage = "Upload";
        });
      } else {
        setState(() {
          _hasUploaded = false;
          _preUploadMessage = "unlink and link account";
        });
      }
    }
  }

  Future<bool> fileExistsInDropbox() async {
    var error_text = "expired_access_token";
    final result = await Dropbox.getTemporaryLink('/${tempFileName}.aac');
    if (result!.contains(error_text)) {
      return false;
    }
    return true;
  }

  Future initDropbox() async {
    await Dropbox.init(dropbox_clientId, dropbox_key, dropbox_secret);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('dropboxAccessToken');
    credentials = prefs.getString('dropboxCredentials');
    final _credentials = await Dropbox.getCredentials();
  }

  Future<bool> checkAuthorized(bool authorize) async {
    final _credentials = await Dropbox.getCredentials();
    if (_credentials != null) {
      if (credentials == null || _credentials!.isEmpty) {
        credentials = _credentials;
        SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.setString('dropboxCredentials', credentials!);
      }
      return true;
    }

    final token = await Dropbox.getAccessToken();
    if (token != null) {
      if (accessToken == null || accessToken!.isEmpty) {
        accessToken = token;
        SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.setString('dropboxAccessToken', accessToken!);
      }
      return true;
    }

    if (authorize) {
      if (credentials != null && credentials!.isNotEmpty) {
        await Dropbox.authorizeWithCredentials(credentials!);
        final _credentials = await Dropbox.getCredentials();
        if (_credentials != null) {
          print('authorizeWithCredentials!');
          return true;
        }
      }
      if (accessToken != null && accessToken!.isNotEmpty) {
        await Dropbox.authorizeWithAccessToken(accessToken!);
        final token = await Dropbox.getAccessToken();
        if (token != null) {
          print('authorizeWithAccessToken!');
          return true;
        }
      } else {
        await Dropbox.authorize();
        print('authorize!');
      }
    }
    return false;
  }

  Future authorize() async {
    await Dropbox.authorize();
  }

  Future unlinkToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.remove('dropboxAccessToken');

    setState(() {
      accessToken = null;
    });
    await Dropbox.unlink();
  }

  Future authorizeWithAccessToken() async {
    await Dropbox.authorizeWithAccessToken(accessToken!);
  }

  Future authorizeWithCredentials() async {
    await Dropbox.authorizeWithCredentials(credentials!);
  }

  Future<String?> getTemporaryLink(path) async {
    final result = await Dropbox.getTemporaryLink(path);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Whisper voice diary'),
      ),
      body: showInstruction
          ? Instructions()
          : Builder(
              builder: (context) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      children: <Widget>[
                        ElevatedButton(
                          child: Text('authorize'),
                          onPressed: authorize,
                        ),
                        ElevatedButton(
                          child: Text('unlink'),
                          onPressed: unlinkToken,
                        ),
                      ],
                    ),
                    Wrap(
                      children: <Widget>[
                        ElevatedButton(
                          child: Text(_isRecording ? (_isPaused ? "Resume recording (${_recordingSeconds})" : "Pause recording (${_recordingSeconds})") : "Start recording"),
                          onPressed: () async {
                            if (_isRecording) {
                              await toggleRecording();
                            } else {
                              await startRecording();
                            }
                          }
                        ),
                      ]
                    ),
                    Wrap(
                      children: <Widget>[
                        ElevatedButton(
                          child: Text(_isRecording ? "Stop recording" : "Please start recording"),
                          onPressed: _isRecording ? () async {
                            await stopRecording();
                          } : null,
                        ),
                      ]
                    ),
                    Wrap(
                      children: <Widget>[
                        ElevatedButton(
                          child: Text(_hasRecorded ? (_hasUploaded ? "Uploaded" : (_isUploading ? "Progress: $_uploadProgress %" : _preUploadMessage)) : "Please record first"),
                          onPressed: _hasRecorded && !_hasUploaded ? () async {
                            await uploadVoiceRecording();
                          } : null,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class Instructions extends StatelessWidget {
  const Instructions({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
              'You need to get dropbox_key & dropbox_secret from https://www.dropbox.com/developers'),
          SizedBox(height: 20),
          Text('1. Update dropbox_key and dropbox_secret from main.dart'),
          SizedBox(height: 20),
          Text(
              "  const String dropbox_key = 'DROPBOXKEY';\n  const String dropbox_secret = 'DROPBOXSECRET';"),
          SizedBox(height: 20),
          Text(
              '2. (Android) Update dropbox_key from android/app/src/main/AndroidManifest.xml.\n  <data android:scheme="db-DROPBOXKEY" />'),
          SizedBox(height: 20),
          Text(
              '2. (iOS) Update dropbox_key from ios/Runner/Info.plist.\n  <string>db-DROPBOXKEY</string>'),
        ],
      ),
    );
  }
}