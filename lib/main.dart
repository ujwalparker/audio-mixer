import 'dart:io';
import 'dart:core';
import 'dart:async';

import 'common.dart';
import 'utils.dart';

import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:ffmpeg_kit_flutter/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter/media_information_session.dart';
import 'package:ffmpeg_kit_flutter/log.dart';
import 'package:ffmpeg_kit_flutter/session.dart';
import 'package:ffmpeg_kit_flutter/statistics.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
  await Firebase.initializeApp();
  print('Handling a background message ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  //
  await Firebase.initializeApp();
  //
  // Set the background messaging handler early on, as a named top-level function
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  //
  if (!kIsWeb) {
    /// Update the iOS foreground notification presentation options to allow
    /// heads up notifications.
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }
  //
  runApp(MixingDemo());
}

class MixingDemo extends StatefulWidget {
  MixingDemo({Key? key}) : super(key: key);

  @override
  _MixingDemoState createState() => _MixingDemoState();
}

class _MixingDemoState extends State<MixingDemo> {
  late final AudioPlayer _audioPlayer = AudioPlayer();
  double _audioPlayerPitch = 1;
  bool _audioControls = false;
  bool _audioInformation = false;
  bool _audioProcessing = false;
  String output = "";
  String audioFolderPath = "audio";

  Stream<PositionData> get _positionDataStream => Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(_audioPlayer.positionStream, _audioPlayer.bufferedPositionStream,
      _audioPlayer.durationStream, (position, bufferedPosition, duration) => PositionData(position, bufferedPosition, duration ?? Duration.zero));

  @override
  void initState() {
    super.initState();
    //
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.black,
    ));
    _audioPlayer.setAsset('audio/recording-english-malayalam.m4a');
    _audioPlayer.setPitch(_audioPlayerPitch);
    //
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print(message.data);
      }
    });
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      if (notification != null && android != null && !kIsWeb) {
        print(notification.body);
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('A new onMessageOpenedApp event was published!');
      print(message.data);
    });
    //
    FFmpegKitConfig.init().then((value) {
      FFmpegKitConfig.getFFmpegVersion().then((version) {
        ffprint("FFmpeg Kit version : $version");
      });
      //
    }).catchError((error) {
      print(error);
    });
    //
    setState(() {});
  }

  void _writeToFile(ByteData data, String path) async {
    final buffer = data.buffer;
    File file = new File(path);
    //
    file.writeAsBytesSync(buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  Future<void> _moveFileFromAssetsToExternalDisk(BuildContext context, String fileName) async {
    try {
      Directory appDocDir = await getExternalStorageDirectory() as Directory;
      //
      String file = join(appDocDir.path, fileName);
      //
      _writeToFile(await DefaultAssetBundle.of(context).load(join(audioFolderPath, fileName)), file);
      //
      await checkMediaInformation(file);
      //
    } catch (e) {
      print(e);
    }
  }

  void _audioControlsVisibility(bool hidden) {
    setState(() {
      _audioControls = hidden;
    });
  }

  void _audioProcessingVisiblity(bool processing) {
    setState(() {
      _audioProcessing = processing;
    });
  }

  void _audioInformationVisiblity(bool information) {
    setState(() {
      _audioInformation = information;
    });
  }

  Future<void> getFFmpegVersion() async {
    ffprint("*************   getFFmpegVersion ************* ");
    await FFmpegKitConfig.getFFmpegVersion().then((version) {
      output = version.toString();
      _audioControlsVisibility(false);
      _audioInformationVisiblity(true);
    }).catchError((error) {
      output = error.toString();
      _audioControlsVisibility(false);
      _audioInformationVisiblity(true);
    });
    ffprint("*************   getFFmpegVersion ************* ");
    _audioProcessingVisiblity(false);
  }

  Future<void> checkMediaInformation(String mediaFile) async {
    try {
      await FFprobeKit.getMediaInformationAsync(mediaFile, (Session session) async {
        // CALLED WHEN SESSION IS EXECUTED
        //
        final returnCode = await session.getReturnCode();
        final failStackTrace = await session.getFailStackTrace();
        //
        if (ReturnCode.isSuccess(returnCode)) {
          // SUCCESS
          final information = (session as MediaInformationSession).getMediaInformation();
          final rcvdFilename = information!.getFilename();
          //
          output = "File : " + information.getFilename().toString() + "\nDuration : " + information.getDuration().toString();
          //
          ffprint("SUCCESS ${notNull(rcvdFilename, "\n")}");
          _audioControlsVisibility(false);
          _audioInformationVisiblity(true);
        } else if (ReturnCode.isCancel(returnCode)) {
          // CANCEL
          ffprint("CANCELLED ${notNull(failStackTrace, "\n")}");
          _audioControlsVisibility(false);
          _audioInformationVisiblity(false);
        } else {
          // ERROR
          ffprint("ERROR ${notNull(failStackTrace, "\n")}");
          _audioControlsVisibility(false);
          _audioInformationVisiblity(false);
        }
        //
        _audioProcessingVisiblity(false);
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> modifyPitch(BuildContext context, String file, int sampleRate, double pitch, double tempo) async {
    Directory appDocDir = await getExternalStorageDirectory() as Directory;
    //
    // https://www.ffmpeg.org/ffmpeg-filters.html#toc-atempo
    // ffmpeg -i file.m4a -af asetrate=44100*0.9,aresample=44100,atempo=3 output-file-44100-3.m4a
    var command = [
      "",
    ];
    //
    String audioFile = join(appDocDir.path, file);
    //
    if (!new File(audioFile).existsSync() || !new File(audioFile).existsSync()) await _moveFileFromAssetsToExternalDisk(context, file);
    //
    output = join(appDocDir.path, [UniqueKey().toString()].join("-") + ".m4a");
    //
    command.add("-i");
    command.add(audioFile);
    command.add("-filter_complex");
    command.add(["asetrate=" + (sampleRate * pitch).toString(), "aresample=" + sampleRate.toString(), "atempo=" + tempo.toString()].join(","));
    command.addAll(["-y", output]);
    //
    print(command.join(" "));
    //
    await FFmpegKit.executeAsync(command.join(" "), (Session session) async {
      // CALLED WHEN SESSION IS EXECUTED
      //
      final returnCode = await session.getReturnCode();
      final failStackTrace = await session.getFailStackTrace();
      //
      if (ReturnCode.isSuccess(returnCode)) {
        ffprint("SUCCESS");
        //
        _audioPlayer.setFilePath(output);
        //
        _audioControlsVisibility(true);
        _audioInformationVisiblity(true);
      } else if (ReturnCode.isCancel(returnCode)) {
        // CANCEL
        ffprint("CANCELLED ${notNull(failStackTrace, "\n")}");
        //
        _audioControlsVisibility(false);
        _audioInformationVisiblity(false);
      } else {
        // ERROR
        ffprint("ERROR ${notNull(failStackTrace, "\n")}");
        //
        _audioControlsVisibility(false);
        _audioInformationVisiblity(false);
      }
      //
      _audioProcessingVisiblity(false);
    }, (Log log) {
      ffprint(log.getMessage());
    }, (Statistics statistics) {
      print(statistics);
    });
  }

  Future<void> mixFiles(BuildContext context, List<String> files) async {
    Directory appDocDir = await getExternalStorageDirectory() as Directory;
    //
    // https://www.ffmpeg.org/ffmpeg-filters.html#toc-amix
    // ffmpeg -i file_1.m4a -i file_2.m4a -filter_complex amix=inputs=2:duration=longest:weights="1 5" output-amix-2.m4a
    // ffmpeg -i file_1.m4a -i file_2.m4a -i file_3.m4a -filter_complex amix=inputs=3:duration=longest:weights="1 5 2" output-amix-3.m4a
    var command = [
      "",
    ];
    int audioCount = 0;
    //
    files.forEach((file) async {
      String audioFile = join(appDocDir.path, file);
      //
      if (!new File(audioFile).existsSync() || !new File(audioFile).existsSync()) await _moveFileFromAssetsToExternalDisk(context, file);
      //
      command.add("-i");
      command.add(audioFile);
      //
      audioCount++;
    });
    //
    output = join(appDocDir.path, [UniqueKey().toString()].join("-") + ".m4a");
    command.addAll(["-filter_complex", "amix=inputs=" + audioCount.toString() + ":duration=longest", "-y", output]); // :weights='1 4' for weightage in volume
    //
    print(command.join(" "));
    //
    if (audioCount > 0) {
      await FFmpegKit.executeAsync(command.join(" "), (Session session) async {
        // CALLED WHEN SESSION IS EXECUTED
        //
        final returnCode = await session.getReturnCode();
        final failStackTrace = await session.getFailStackTrace();
        //
        if (ReturnCode.isSuccess(returnCode)) {
          ffprint("SUCCESS");
          //
          _audioPlayer.setFilePath(output);
          //
          _audioControlsVisibility(true);
          _audioInformationVisiblity(true);
        } else if (ReturnCode.isCancel(returnCode)) {
          // CANCEL
          ffprint("CANCELLED ${notNull(failStackTrace, "\n")}");
          //
          _audioControlsVisibility(false);
          _audioInformationVisiblity(false);
        } else {
          // ERROR
          ffprint("ERROR ${notNull(failStackTrace, "\n")}");
          //
          _audioControlsVisibility(false);
          _audioInformationVisiblity(false);
        }
        //
        _audioProcessingVisiblity(false);
      }, (Log log) {
        ffprint(log.getMessage());
      }, (Statistics statistics) {
        print(statistics);
      });
    } else {
      print("No audio file to Mix");
    }
  }

  Future<void> mergeFiles(BuildContext context, List<String> files) async {
    Directory appDocDir = await getExternalStorageDirectory() as Directory;
    //
    // https://www.ffmpeg.org/ffmpeg-filters.html#toc-concat
    // ffmpeg -i foreground.m4a -i background.m4a -filter_complex concat=n=2:v=0:a=1 -vn -y output-concat.m4a
    var command = [
      "",
    ];
    //
    int audioCount = 0;
    //
    files.forEach((file) async {
      String audioFile = join(appDocDir.path, file);
      //
      if (!new File(audioFile).existsSync()) await _moveFileFromAssetsToExternalDisk(context, file);
      //
      command.add("-i");
      command.add(audioFile);
      //
      audioCount++;
    });
    //
    output = join(appDocDir.path, [UniqueKey().toString()].join("-") + ".m4a");
    command.addAll(["-filter_complex", "concat=n=" + audioCount.toString() + ":v=0:a=1", "-vn", "-y", output]);
    //
    print(command.join(" "));
    //
    if (audioCount > 0) {
      await FFmpegKit.executeAsync(command.join(" "), (Session session) async {
        // CALLED WHEN SESSION IS EXECUTED
        //
        final returnCode = await session.getReturnCode();
        final failStackTrace = await session.getFailStackTrace();
        //
        if (ReturnCode.isSuccess(returnCode)) {
          ffprint("SUCCESS");
          //
          _audioPlayer.setFilePath(output);
          //
          _audioControlsVisibility(true);
          _audioInformationVisiblity(true);
        } else if (ReturnCode.isCancel(returnCode)) {
          // CANCEL
          ffprint("CANCELLED ${notNull(failStackTrace, "\n")}");
          //
          _audioControlsVisibility(false);
          _audioInformationVisiblity(false);
        } else {
          // ERROR
          ffprint("ERROR ${notNull(failStackTrace, "\n")}");
          //
          _audioControlsVisibility(false);
          _audioInformationVisiblity(false);
        }
        //
        _audioProcessingVisiblity(false);
      }, (Log log) {
        ffprint(log.getMessage());
      }, (Statistics statistics) {
        print(statistics);
      });
    } else {
      print("No audio file to Merge");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text("Audio Mixer Demo"),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Center(
                      child: ElevatedButton(
                        onPressed: () async {
                          _audioPlayer.stop();
                          //
                          _audioControlsVisibility(false);
                          _audioInformationVisiblity(false);
                          _audioProcessingVisiblity(true);
                          //
                          await getFFmpegVersion();
                        },
                        child: Text('FFmpegVersion'),
                      ),
                    )
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Center(
                      child: ElevatedButton(
                        onPressed: () async {
                          _audioPlayer.stop();
                          //
                          _audioControlsVisibility(false);
                          _audioInformationVisiblity(false);
                          _audioProcessingVisiblity(true);
                          //
                          await _moveFileFromAssetsToExternalDisk(context, "recording-english-mumbai.m4a"); // "audio/background-on-the-happy-side-whistling.m4a"
                        },
                        child: Text('Check Media Information'),
                      ),
                    )
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Center(
                      child: ElevatedButton(
                        onPressed: () async {
                          _audioPlayer.stop();
                          //
                          _audioControlsVisibility(false);
                          _audioInformationVisiblity(false);
                          _audioProcessingVisiblity(true);
                          //
                          var files = ["recording-english-tamil.m4a", "effect-young-man-coughing.m4a", "recording-english-malayalam.m4a", "effect-crowd-laugh.m4a", "recording-english-swedish.m4a"];
                          //
                          await mergeFiles(context, files);
                        },
                        child: Text('Merge - Concatenate audio files'),
                      ),
                    )
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Center(
                      child: ElevatedButton(
                        onPressed: () async {
                          _audioPlayer.stop();
                          //
                          _audioControlsVisibility(false);
                          _audioInformationVisiblity(false);
                          _audioProcessingVisiblity(true);
                          //
                          var files = ["recording-english-mumbai.m4a", "background-nature-lake-ambience.m4a"];
                          //
                          await mixFiles(context, files);
                        },
                        child: Text('Mix - Foreground & Background'),
                      ),
                    )
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Center(
                      child: ElevatedButton(
                        onPressed: () async {
                          _audioPlayer.stop();
                          //
                          _audioControlsVisibility(false);
                          _audioInformationVisiblity(false);
                          _audioProcessingVisiblity(true);
                          //
                          /*
                          Woman -     1.25/pitch, 1.25/tempo
                          Man -       0.75/pitch, 1.25/tempo
                          Child -     2.00/pitch,  0.75/tempo
                          Orginal -   1.00/pitch,  1.00/tempo
                          */
                          List pitchByGender(String gender) {
                            switch (gender) {
                              case "Woman":
                                return [1.25, 1.25];
                              case "Man":
                                return [0.75, 1.25];
                              case "Child":
                                return [2.00, 0.75];
                              default:
                                return [1.00, 1.00];
                            }
                          }

                          //
                          final gender = "Woman";
                          //
                          final int sampleRate = 44100;
                          final double pitch = pitchByGender(gender)[0];
                          final double tempo = pitchByGender(gender)[1];
                          //
                          await modifyPitch(context, "recording-english-swedish.m4a", sampleRate, pitch, tempo);
                        },
                        child: Text("Modify Pitch"),
                      ),
                    )
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox.fromSize(size: new Size(10, 60)),
                    !_audioProcessing ? const SizedBox.shrink() : CircularProgressIndicator(),
                    !_audioControls
                        ? const SizedBox.shrink()
                        : Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ControlButtons(_audioPlayer),
                                StreamBuilder<PositionData>(
                                  stream: _positionDataStream,
                                  builder: (context, snapshot) {
                                    final positionData = snapshot.data;
                                    return SeekBar(
                                      duration: positionData?.duration ?? Duration.zero,
                                      position: positionData?.position ?? Duration.zero,
                                      bufferedPosition: positionData?.bufferedPosition ?? Duration.zero,
                                      onChangeEnd: _audioPlayer.seek,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                  ],
                ),
                Row(
                  children: [
                    !_audioInformation
                        ? const SizedBox.shrink()
                        : Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [Center(child: Container(padding: EdgeInsets.fromLTRB(20, 20, 20, 20), child: Text(output, style: TextStyle(fontSize: 12))))],
                            ),
                          ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    //
    super.dispose();
  }
}

class ControlButtons extends StatelessWidget {
  final AudioPlayer _audioPlayer;

  ControlButtons(this._audioPlayer);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.volume_up),
          onPressed: () {
            showSliderDialog(
              context: context,
              title: "Adjust volume",
              divisions: 10,
              min: 0.0,
              max: 1.0,
              value: _audioPlayer.volume,
              stream: _audioPlayer.volumeStream,
              onChanged: _audioPlayer.setVolume,
            );
          },
        ),
        StreamBuilder<PlayerState>(
          stream: _audioPlayer.playerStateStream,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final processingState = playerState?.processingState;
            final playing = playerState?.playing;
            if (processingState == ProcessingState.loading || processingState == ProcessingState.buffering) {
              return Container(
                margin: EdgeInsets.all(8.0),
                width: 64.0,
                height: 64.0,
                child: CircularProgressIndicator(),
              );
            } else if (playing != true) {
              return IconButton(
                icon: Icon(Icons.play_arrow),
                iconSize: 64.0,
                onPressed: _audioPlayer.play,
              );
            } else if (processingState != ProcessingState.completed) {
              return IconButton(
                icon: Icon(Icons.pause),
                iconSize: 64.0,
                onPressed: _audioPlayer.pause,
              );
            } else {
              return IconButton(
                icon: Icon(Icons.replay),
                iconSize: 64.0,
                onPressed: () => _audioPlayer.seek(Duration.zero),
              );
            }
          },
        ),
        StreamBuilder<double>(
          stream: _audioPlayer.speedStream,
          builder: (context, snapshot) => IconButton(
            icon: Text("${snapshot.data?.toStringAsFixed(1)}x", style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              showSliderDialog(
                context: context,
                title: "Adjust speed",
                divisions: 10,
                min: 0.5,
                max: 1.5,
                value: _audioPlayer.speed,
                stream: _audioPlayer.speedStream,
                onChanged: _audioPlayer.setSpeed,
              );
            },
          ),
        ),
      ],
    );
  }
}
