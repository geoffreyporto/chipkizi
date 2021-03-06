import 'dart:async';
import 'package:chipkizi/models/user.dart';
import 'package:chipkizi/values/consts.dart';
import 'package:chipkizi/values/strings.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:chipkizi/models/recording.dart';
import 'package:chipkizi/values/status_code.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:flutter_sound/flutter_sound.dart';
// import 'dart:io';
// import 'package:uuid/uuid.dart';

const _tag = 'RecordingModel:';

abstract class RecordingModel extends Model {
  final Firestore _database = Firestore.instance;
  final FirebaseStorage storage = FirebaseStorage();
//  AudioCache audioCache =  AudioCache();

  FlutterSound flutterSound = FlutterSound();
  List<String> _selectedGenres = <String>[];
  Recording _lastSubmittedRecording;
  Recording get lastSubmittedRecording => _lastSubmittedRecording;

  Stream<QuerySnapshot> recordingsStream = Firestore.instance
      .collection(RECORDINGS_COLLECTION)
      .orderBy(CREATED_AT_FIELD, descending: true)
      .snapshots();

  String _defaultRecordingPath;
  String get defaultRecordingPath => _defaultRecordingPath;
  bool get isReadyToSubmit => _defaultRecordingPath != null;
  
  StreamSubscription _recorderSubscription;

  StatusCode _submitStatus;
  StatusCode get submitStatus => _submitStatus;
  StatusCode _editingRecordingDetailsStatus;
  StatusCode get editingRecordingDetailsStatus =>
      _editingRecordingDetailsStatus;
  bool _isEditingRecordingTitle = false;
  bool get isEditingTitle => _isEditingRecordingTitle;
  bool _isEditingRecordingDesc = false;
  bool get isEditingRecordingDesc => _isEditingRecordingDesc;
  bool _isRecording = false;
  bool get isRecording => _isRecording;
  String _recorderTxt = '00:00:00';
  String get recorderTxt => _recorderTxt;
  double _recorderProgress = 0.0;
  double get recorderProgress => _recorderProgress;
  String _tempTitle;
  String get tempTitle => _tempTitle;
  String _tempDescription;
  String get tempDescription => _tempDescription;

  Map<String, bool> genres = <String, bool>{
    'Gospel': false,
    'Inpirational quotes': false,
    'Instrumental': false,
    'Hip-hop': false,
    'Bongo flava': false,
    'Poem': false,
    'Spoken word': false,
    'R&B': false,
    'Speech': false,
    'Music': false,
    'Comedy': false,
    'Other': false,
  };

  void setTempValues(String value, DetailType type) {
    print('$_tag at setTempValues');
    switch (type) {
      case DetailType.title:
        _tempTitle = value;
        notifyListeners();
        break;
      case DetailType.description:
        _tempDescription = value;
        notifyListeners();
        break;
      default:
        print('$_tag unexpected type: $type');
    }
  }

  void updateGenres(int index) {
    genres.update(genres.keys.elementAt(index),
        (isSelected) => isSelected ? false : true);
    notifyListeners();
  }

  void resetSubmitStatus() {
    _lastSubmittedRecording = null;
    _submitStatus = null;
  }

  void resetTempDetailsFieldValues() {
    _tempTitle = null;
    _tempDescription = null;
    notifyListeners();
  }

  setSubmitStatus() {
    _submitStatus = StatusCode.waiting;
    notifyListeners();
  }

  Future<StatusCode> handleSubmit(Recording recording) async {
    print('$_tag at handle submit recording');
    _submitStatus = await _createRecordingDoc(recording);
    return _submitStatus;
  }

  Future<Recording> _refineRecording(Recording recording) async {
    print('$_tag create notification doc');
    bool _hasError = false;
    DocumentSnapshot document = await _database
        .collection(USERS_COLLECTION)
        .document(recording.createdBy)
        .get()
        .catchError((error) {
      print('$_tag error on getting user document');
      _hasError = true;
    });
    if (_hasError || !document.exists) return recording;
    User user = User.fromSnapshot(document);
    if (user == null) return recording;
    recording.username = user.name;
    recording.userImageUrl = user.imageUrl;

    return recording;
  }

  Future<void> _createNotificationDoc(Recording recording) async {
    print('$_tag at _createNotificationDoc');
    Recording refinedRecording = await _refineRecording(recording);
    final username = refinedRecording.username != null
        ? refinedRecording.username
        : APP_NAME;
    Map<String, dynamic> notificationMap = {
      TITLE_FIELD: newRecordingText,
      BODY_FIELD:
          '${refinedRecording.title}\n$username\n${refinedRecording.description}',
      ID_FIELD: recording.id,
      FIELD_NOTIFICATION_TYPE: FIELD_NOTIFICATION_TYPE_NEW_RECORDING,
    };
    _database
        .collection(MESSAGES_COLLECTION)
        .add(notificationMap)
        .catchError((error) {
      print('$_tag error on creating notication doc');
    });
  }

  Future<StatusCode> _createRecordingDoc(Recording recording) async {
    print('$_tag at _createRecordingDoc');
    bool _hasError = false;
    List<String> tempList = <String>[];
    genres.forEach((genre, isSelected) {
      if (isSelected) tempList.add(genre);
    });
    _selectedGenres = tempList;
    Map<String, dynamic> recordingMap = {
      RECORDING_URL_FIELD: recording.recordingUrl,
      RECORDING_PATH_FIELD: recording.recordingPath,
      CREATED_BY_FIELD: recording.createdBy,
      CREATED_AT_FIELD: recording.createdAt,
      TITLE_FIELD: recording.title,
      DESCRIPTION_FIELD: recording.description,
      UPVOTE_COUNT_FIELD: 0,
      PLAY_COUNT_FIELD: 0,
      GENRE_FIELD: _selectedGenres
    };
    DocumentReference document = await _database
        .collection(RECORDINGS_COLLECTION)
        .add(recordingMap)
        .catchError((error) {
      print('$_tag error on creating recording doc: $error');
      _hasError = true;
    });
    recording.id = document.documentID;
    _lastSubmittedRecording = await getRecordingFromId(recording.id);
    notifyListeners();
    _createUserRecordingDocRef(recording);
    _createNotificationDoc(recording);
    if (_hasError) return StatusCode.failed;
    return StatusCode.success;
  }

  Future<StatusCode> _createUserRecordingDocRef(Recording recording) async {
    print('$_tag at _createUserRecordingDocRef');
    bool _hasError = false;
    Map<String, dynamic> refMap = {
      CREATED_BY_FIELD: recording.createdBy,
      CREATED_AT_FIELD: recording.createdAt,
      RECORDING_ID_FIELD: recording.id,
    };
    await _database
        .collection(USERS_COLLECTION)
        .document(recording.createdBy)
        .collection(RECORDINGS_COLLECTION)
        .document(recording.id)
        .setData(refMap)
        .catchError((error) {
      print('$_tag error on creating a recording reference for user: $error');
      _hasError = true;
    });
    if (_hasError) return StatusCode.failed;
    return StatusCode.success;
  }

  Future<void> startRecording() async {
    print('$_tag at startRecording');
    try {
      String path = await flutterSound.startRecorder(null);
      print('startRecorder: $path');
      _defaultRecordingPath = path;
      notifyListeners();

      _recorderSubscription = flutterSound.onRecorderStateChanged.listen((e) {
        DateTime date =
            DateTime.fromMillisecondsSinceEpoch(e.currentPosition.toInt());

        String txt = DateFormat('mm:ss:SS', 'en_US').format(date);
        _recorderTxt = txt.substring(0, 8);
        int lapsedTime = date.second;
        int totalTime = 30;
        _recorderProgress = lapsedTime / totalTime;
        if (_recorderTxt == '00:30:00') stopRecording();

        print('$_recorderProgress');
        notifyListeners();
      });

      _isRecording = true;
      notifyListeners();
    } catch (err) {
      print('startRecorder error: $err');
    }
  }

  Future<void> stopRecording() async {
    print('$_tag at stopRecording');
    try {
      String result = await flutterSound.stopRecorder();
      print('stopRecorder: $result');

      if (_recorderSubscription != null) {
        _recorderSubscription.cancel();
        _recorderSubscription = null;
      }

      this._isRecording = false;
      notifyListeners();
    } catch (err) {
      print('stopRecorder error: $err');
    }
  }

  /// called when the user clicks the  edit recording details icon
  /// the [type] is a [DetailType] that will be passed to indicate
  /// which field the user is updating
  /// the [type] is for the edit recording is limited to
  /// [DetailType.title] and [DetailType.description]
  void startEditingRecordingDetails(DetailType type) {
    print('$_tag at startEditingName');
    switch (type) {
      case DetailType.title:
        _isEditingRecordingTitle = true;
        notifyListeners();
        break;
      case DetailType.description:
        _isEditingRecordingDesc = true;
        notifyListeners();
        break;
      default:
        print('$_tag unexpected type: $type');
    }
  }

  /// called to reset the is editing fields when he user has
  /// finished editing the respective fields
  /// the [type] is a [DetailType] a function will pass
  /// to specify the field that needs reset
  /// the [type] on isEditing fields will be limited to
  /// [DetailType.title] which will reset the [_isEditingRecordingTitle] field to [false]
  /// and teh [DetailType.description] which will reset the [_isEditingRecordingDesc] field to [false]
  _resetIsEditingField(DetailType type) {
    switch (type) {
      case DetailType.title:
        _isEditingRecordingTitle = false;
        break;
      case DetailType.description:
        _isEditingRecordingDesc = false;
        break;
      default:
        print('$_tag unexpected type: $type');
    }
  }

  /// editRecordingDetails is called when the user finishes entering new detail
  /// after clicking the edit recording details icon
  /// the [recording] is of type [Recording] which is the user who is editing the recording details
  /// the [user] is typically the currenttly logged in user
  /// the [DetailType] [type] is the specific field that the user is currently editing
  /// the [type] for editRecordingDetails is limited to [DetailType.name] and [DetailType.bio]

  Future<StatusCode> editRecordingDetails(
      Recording recording, DetailType type) async {
    print('$_tag at editRecordingDetails');
    _editingRecordingDetailsStatus = StatusCode.waiting;
    switch (type) {
      case DetailType.title:
        _isEditingRecordingTitle = true;
        break;
      case DetailType.description:
        _isEditingRecordingDesc = true;
        break;
      default:
        print('$_tag unexpected type: $type');
    }
    notifyListeners();
    bool _hasError = false;
    Map<String, dynamic> detailMap = Map();
    switch (type) {
      case DetailType.title:
        detailMap.putIfAbsent(TITLE_FIELD, () => recording.title);
        break;
      case DetailType.description:
        detailMap.putIfAbsent(DESCRIPTION_FIELD, () => recording.description);
        break;
      default:
        print('$_tag unexpected detail type: $type');
    }
    await _database
        .collection(RECORDINGS_COLLECTION)
        .document(recording.id)
        .updateData(detailMap)
        .catchError((error) {
      print('$_tag error on updating user details: $error');
      _editingRecordingDetailsStatus = StatusCode.failed;
      _hasError = true;
      _resetIsEditingField(type);
      notifyListeners();
    });
    if (_hasError) return _editingRecordingDetailsStatus;
    _editingRecordingDetailsStatus = StatusCode.success;
    _resetIsEditingField(type);
    notifyListeners();
    return _editingRecordingDetailsStatus;
  }

  Future<Recording> getRecordingFromId(String id) async {
    print('$_tag at _getRecordingFromId');
    bool _hasError = false;
    DocumentSnapshot document = await _database
        .collection(RECORDINGS_COLLECTION)
        .document(id)
        .get()
        .catchError((error) {
      print('$_tag error on getting recording from id: $error');
      _hasError = true;
    });
    if (_hasError) return null;
    if (!document.exists) return null;
    return Recording.fromSnaspshot(document);
  }
}
