import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:typed_data';
import 'package:timezone/data/latest.dart' as tz;
import 'package:app_settings/app_settings.dart';
import 'package:http/http.dart' as http;

// 알람 스케줄 클래스 정의
class AlarmSchedule {
  final int id;
  final TimeOfDay time;
  final List<bool> days;
  final String stationName;
  bool isEnabled;

  AlarmSchedule({
    required this.id,
    required this.time,
    required this.days,
    required this.stationName,
    this.isEnabled = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'time': {'hour': time.hour, 'minute': time.minute},
      'days': days,
      'isEnabled': isEnabled,
      'stationName': stationName,
    };
  }

  factory AlarmSchedule.fromJson(Map<String, dynamic> json) {
    final time = json['time'];
    return AlarmSchedule(
      id: json['id'],
      time: TimeOfDay(hour: time['hour'], minute: time['minute']),
      days: List<bool>.from(json['days']),
      isEnabled: json['isEnabled'],
      stationName: json['stationName'],
    );
  }
}

// 역 검색 다이얼로그 위젯
class StationSearchDialog extends StatefulWidget {
  final List<dynamic> allStations;

  const StationSearchDialog({Key? key, required this.allStations}) : super(key: key);

  @override
  _StationSearchDialogState createState() => _StationSearchDialogState();
}

// 역 검색 다이얼로그 상태 클래스
class _StationSearchDialogState extends State<StationSearchDialog> {
  String searchQuery = '';
  List<Map<String, dynamic>> searchResults = [];
  TextEditingController searchController = TextEditingController();

  void performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        searchResults = [];
      });
      return;
    }

    var matches = widget.allStations.where((station) =>
        station['station_nm'].toString().toLowerCase().contains(query.toLowerCase())
    ).toList();

    var uniqueStations = <Map<String, dynamic>>{};
    for (var station in matches) {
      uniqueStations.add({
        'station_nm': station['station_nm'],
        'line_num': station['line_num']
      });
    }

    setState(() {
      searchResults = uniqueStations.toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        padding: EdgeInsets.all(16),
        constraints: BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '역 검색',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            SizedBox(height: 16),
            TextField(
              controller: searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '역 이름을 입력하세요',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: performSearch,
            ),
            SizedBox(height: 16),
            Flexible(
              child: searchResults.isEmpty
                  ? Center(
                child: Text(
                  searchQuery.isEmpty
                      ? '역 이름을 입력해주세요'
                      : '검색 결과가 없습니다',
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),
              )
                  : ListView.separated(
                shrinkWrap: true,
                itemCount: searchResults.length,
                separatorBuilder: (context, index) => Divider(height: 1),
                itemBuilder: (context, index) {
                  final station = searchResults[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.withOpacity(0.1),
                      child: Icon(
                        Icons.train,
                        color: Colors.blue,
                      ),
                    ),
                    title: Text(station['station_nm']),
                    subtitle: Text('${station['line_num']}호선'),
                    onTap: () {
                      Navigator.pop(context, station['station_nm']);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 타이머 스크린 위젯
class TimerScreen extends StatefulWidget {
  @override
  TimerScreenState createState() => TimerScreenState();
}

// 타이머 스크린 상태 클래스
class TimerScreenState extends State<TimerScreen> {
  List<AlarmSchedule> alarms = [];
  List<bool> selectedDays = List.generate(7, (index) => false);
  TimeOfDay selectedTime = TimeOfDay.now();
  late SharedPreferences prefs;
  bool isInitialized = false;
  List<dynamic> allStations = [];
  String? selectedStation;
  bool isLoading = false;
  String currentLine = '1';
  final List<String> subwayLines = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];

  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  String _getSubwayId(String line) {
    Map<String, String> lineIds = {
      '1': '1001',
      '2': '1002',
      '3': '1003',
      '4': '1004',
      '5': '1005',
      '6': '1006',
      '7': '1007',
      '8': '1008',
      '9': '1009',
    };
    return lineIds[line] ?? '1001';
  }

  Future<String> _fetchArrivalInfo(String stationName) async {
    String apiKey = '6f77695050636e64333568746d5370';
    String url = 'http://swopenAPI.seoul.go.kr/api/subway/$apiKey/json/realtimeStationArrival/0/10/$stationName';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        var decodedBody = utf8.decode(response.bodyBytes);
        Map<String, dynamic> data = json.decode(decodedBody);

        if (data.containsKey('realtimeArrivalList')) {
          List<dynamic> arrivals = data['realtimeArrivalList'];

          // 상행과 하행 정보를 저장할 변수
          Map<String, String> upTrainInfo = {};
          Map<String, String> downTrainInfo = {};

          for (var arrival in arrivals) {
            String updnLine = arrival['updnLine'] ?? '';
            String barvlDt = arrival['barvlDt'] ?? '';
            String timeUntilArrival = '';

            if (barvlDt.isNotEmpty) {
              try {
                int seconds = int.parse(barvlDt);
                int minutes = (seconds / 60).floor();
                timeUntilArrival = minutes == 0 ? '곧 도착' : '$minutes분 후 도착';
              } catch (e) {
                timeUntilArrival = '시간 정보 없음';
              }
            }

            // 상행/하행 정보 저장
            if (updnLine.contains('상행') && upTrainInfo.isEmpty) {
              upTrainInfo = {
                'direction': arrival['trainLineNm'] ?? '',
                'time': timeUntilArrival,
              };
            } else if (updnLine.contains('하행') && downTrainInfo.isEmpty) {
              downTrainInfo = {
                'direction': arrival['trainLineNm'] ?? '',
                'time': timeUntilArrival,
              };
            }

            // 상행과 하행 모두 찾았다면 반복 중단
            if (upTrainInfo.isNotEmpty && downTrainInfo.isNotEmpty) {
              break;
            }
          }

          // 알림 메시지 생성
          List<String> messages = [];
          if (upTrainInfo.isNotEmpty) {
            messages.add('상행(${upTrainInfo['direction']}): ${upTrainInfo['time']}');
          }
          if (downTrainInfo.isNotEmpty) {
            messages.add('하행(${downTrainInfo['direction']}): ${downTrainInfo['time']}');
          }

          return messages.isEmpty ? '도착 정보가 없습니다.' : messages.join('\n');
        }
      }
      return '도착 정보를 불러올 수 없습니다.';
    } catch (e) {
      print('도착 정보 조회 오류: $e');
      return '도착 정보 조회 중 오류가 발생했습니다.';
    }
  }


  @override
  void initState() {
    super.initState();
    _requestNotificationPermissions();
    _initializeApp();
    _loadStationData();
  }

  Future<void> _loadStationData() async {
    setState(() {
      isLoading = true;
    });

    try {
      String jsonString = await rootBundle.loadString('assets/seoul_subway.json');
      final jsonResponse = json.decode(jsonString);

      if (jsonResponse['DATA'] != null) {
        setState(() {
          allStations = jsonResponse['DATA'];
        });
      }
    } catch (e) {
      print('역 데이터 로딩 오류: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _initializeApp() async {
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

      await _initNotifications();
      prefs = await SharedPreferences.getInstance();
      await _loadAlarms();

      for (var alarm in alarms) {
        if (alarm.isEnabled) {
          await _scheduleNotification(alarm);
        }
      }

      setState(() {
        isInitialized = true;
      });
    } catch (e) {
      print('초기화 중 오류 발생: $e');
    }
  }

  Future<void> _initNotifications() async {
    if (Platform.isAndroid) {
      final androidImplementation =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        final bool? granted = await androidImplementation.requestNotificationsPermission();
        print('알림 권한 상태: $granted');

        if (granted != true && context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('알림 권한 필요'),
              content: const Text('정확한 시간에 알림을 받기 위해서는 알림 권한이 필요합니다. 설정에서 권한을 활성화해주세요.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    AppSettings.openAppSettings();
                  },
                  child: const Text('설정으로 이동'),
                ),
              ],
            ),
          );
          return;
        }
      }
    }

    const androidChannel = AndroidNotificationChannel(
      'alarm_channel_id',
      'Alarm Notifications',
      description: 'Channel for alarm notifications',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      enableLights: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: androidSettings);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        print('알림 응답 받음: ${details.payload}');
      },
    );
  }

  tz.TZDateTime _nextInstanceOfTime(TimeOfDay timeOfDay, List<bool> days) {
    final now = tz.TZDateTime.now(tz.local);

    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      timeOfDay.hour,
      timeOfDay.minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    for (int i = 0; i < 7; i++) {
      final checkDay = (scheduledDate.weekday - 1) % 7;

      if (days[checkDay]) {
        if (i == 0 && !scheduledDate.isBefore(now)) {
          return scheduledDate;
        }
        if (i > 0) {
          return scheduledDate;
        }
      }
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    for (int i = 0; i < 7; i++) {
      if (days[i]) {
        while (scheduledDate.weekday != i + 1) {
          scheduledDate = scheduledDate.add(const Duration(days: 1));
        }
        break;
      }
    }

    return scheduledDate;
  }

  Future<void> _scheduleNotification(AlarmSchedule alarm) async {
    try {
      for (int i = 0; i < alarm.days.length; i++) {
        if (alarm.days[i]) {
          final nextAlarmTime = _nextInstanceOfDayTime(alarm.time, i);

          final androidDetails = AndroidNotificationDetails(
            'alarm_channel_id',
            '지하철 알림',
            channelDescription: 'Channel for alarm notifications',
            importance: Importance.max,
            priority: Priority.max,
            showWhen: true,
            enableVibration: true,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            autoCancel: true,
            ongoing: false,
            playSound: true,
          );

          await flutterLocalNotificationsPlugin.zonedSchedule(
            alarm.id + (i * 1000),
            '지하철 도착 알림',
            '${alarm.stationName}역 도착 시간입니다.',
            nextAlarmTime,
            NotificationDetails(android: androidDetails),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: 'alarm_${alarm.id}_${i}',
          );
        }
      }
    } catch (e) {
      print('알림 예약 실패: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('알림 설정 실패: $e')),
        );
      }
    }
  }

  tz.TZDateTime _nextInstanceOfDayTime(TimeOfDay timeOfDay, int targetDay) {
    final now = tz.TZDateTime.now(tz.local);

    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      timeOfDay.hour,
      timeOfDay.minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    while (scheduledDate.weekday != targetDay + 1) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    return scheduledDate;
  }
  Future<void> _cancelNotification(int alarmId) async {
    for (int i = 0; i < 7; i++) {
      await flutterLocalNotificationsPlugin.cancel(alarmId + (i * 1000));
    }
    print('알림 취소됨: $alarmId');
  }

  Future<void> _requestNotificationPermissions() async {
    if (Platform.isAndroid) {
      final status = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      print('알림 권한 상태: $status');
    }
  }

  Future<void> _saveAlarms() async {
    try {
      final String alarmsJson = jsonEncode(alarms.map((a) => a.toJson()).toList());
      await prefs.setString('alarms', alarmsJson);
      print('알람 저장 완료: $alarmsJson');
    } catch (e) {
      print('알람 저장 실패: $e');
    }
  }

  Future<void> _loadAlarms() async {
    try {
      final String? alarmsJson = prefs.getString('alarms');
      print('로드된 알람 데이터: $alarmsJson');

      if (alarmsJson != null) {
        final List<dynamic> decoded = jsonDecode(alarmsJson);
        setState(() {
          alarms = decoded.map((item) => AlarmSchedule.fromJson(item)).toList();
        });
      }
    } catch (e) {
      print('알람 로드 실패: $e');
    }
  }

  String _getDaysText(List<bool> days) {
    final List<String> dayNames = ['월', '화', '수', '목', '금', '토', '일'];
    final List<String> selectedDays = [];

    for (int i = 0; i < days.length; i++) {
      if (days[i]) selectedDays.add(dayNames[i]);
    }

    return selectedDays.isEmpty ? '요일 미선택' : selectedDays.join(', ');
  }

  Future<void> _toggleAlarm(int index, bool value) async {
    setState(() {
      alarms[index].isEnabled = value;
    });

    if (value) {
      await _scheduleNotification(alarms[index]);
    } else {
      await _cancelNotification(alarms[index].id);
    }

    await _saveAlarms();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? '알림이 활성화되었습니다' : '알림이 비활성화되었습니다'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _showAddAlarmDialog() async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time != null) {
      selectedTime = time;
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: Text('알람 설정'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: Icon(Icons.train),
                      title: Text(selectedStation ?? '역을 선택하세요'),
                      trailing: Icon(Icons.arrow_forward_ios),
                      onTap: () async {
                        final String? selected = await showDialog<String>(
                          context: context,
                          builder: (context) => StationSearchDialog(allStations: allStations),
                        );
                        if (selected != null) {
                          setState(() {
                            selectedStation = selected;
                          });
                        }
                      },
                    ),
                    SizedBox(height: 20),
                    Wrap(
                      spacing: 5,
                      children: [
                        for (int i = 0; i < 7; i++)
                          FilterChip(
                            label: Text(['월', '화', '수', '목', '금', '토', '일'][i]),
                            selected: selectedDays[i],
                            onSelected: (bool selected) {
                              setState(() {
                                selectedDays[i] = selected;
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: Text('취소'),
                  onPressed: () {
                    Navigator.pop(context);
                    selectedStation = null;
                  },
                ),
                TextButton(
                  child: Text('저장'),
                  onPressed: () {
                    if (selectedStation == null) {
                      Navigator.pop(context);
                      if (this.context.mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: Text('역을 선택해주세요')),
                        );
                      }
                      return;
                    }
                    if (selectedDays.every((day) => !day)) {
                      Navigator.pop(context);
                      if (this.context.mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: Text('최소 하나의 요일을 선택해주세요')),
                        );
                      }
                      return;
                    }
                    Navigator.pop(context);
                    _addAlarm();
                  },
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  Future<void> _addAlarm() async {
    final newId = alarms.isEmpty ? 1 : alarms.map((a) => a.id).reduce(max) + 1;

    final newAlarm = AlarmSchedule(
      id: newId,
      time: selectedTime,
      days: List.from(selectedDays),
      stationName: selectedStation!,
      isEnabled: true,
    );

    setState(() {
      alarms.add(newAlarm);
      selectedDays = List.generate(7, (index) => false);
      selectedStation = null;
    });

    await _scheduleNotification(newAlarm);
    await _saveAlarms();
  }

  @override
  Widget build(BuildContext context) {
    if (!isInitialized) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDarkMode ? Colors.white : Colors.black;
    final Color cardColor = isDarkMode ? Colors.grey[800]! : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: Text('알림 설정'),
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Expanded(
            child: alarms.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    '설정된 알림이 없습니다.\n+ 버튼을 눌러 알림을 추가하세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              itemCount: alarms.length,
              itemBuilder: (context, index) {
                final alarm = alarms[index];
                return Dismissible(
                  key: Key(alarm.id.toString()),
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: EdgeInsets.only(right: 20),
                    child: Icon(
                      Icons.delete,
                      color: Colors.white,
                    ),
                  ),
                  direction: DismissDirection.endToStart,
                  onDismissed: (direction) async {
                    setState(() {
                      alarms.removeAt(index);
                    });
                    await _cancelNotification(alarm.id);
                    await _saveAlarms();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('알림이 삭제되었습니다'),
                        action: SnackBarAction(
                          label: '실행 취소',
                          onPressed: () async {
                            setState(() {
                              alarms.insert(index, alarm);
                            });
                            if (alarm.isEnabled) {
                              await _scheduleNotification(alarm);
                            }
                            await _saveAlarms();
                          },
                        ),
                      ),
                    );
                  },
                  child: Card(
                    color: cardColor,
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    elevation: 2,
                    child: ListTile(
                      leading: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: alarm.isEnabled
                              ? Colors.blue.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.subway,
                          color: alarm.isEnabled ? Colors.blue : Colors.grey,
                        ),
                      ),
                      title: Text(
                        '${alarm.time.format(context)} - ${alarm.stationName}역',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 4),
                          Text(
                            _getDaysText(alarm.days),
                            style: TextStyle(color: textColor.withOpacity(0.8)),
                          ),
                          Text(
                            alarm.isEnabled ? '활성화됨' : '비활성화됨',
                            style: TextStyle(
                              color: alarm.isEnabled ? Colors.blue : Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: Switch(
                        value: alarm.isEnabled,
                        onChanged: (value) => _toggleAlarm(index, value),
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
        onPressed: _showAddAlarmDialog,
        icon: Icon(Icons.add),
        label: Text('알림 추가'),
        backgroundColor: Colors.blue,
      ),
    );
  }
}
