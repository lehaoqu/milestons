import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MilestonesApp());
}

class MilestonesApp extends StatelessWidget {
  const MilestonesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '情侣里程碑',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pinkAccent),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const MilestoneHomePage(),
    );
  }
}

enum MilestoneOwner { personA, personB, both }

extension MilestoneOwnerLabel on MilestoneOwner {
  String getLabel(String nameA, String nameB) {
    switch (this) {
      case MilestoneOwner.personA:
        return nameA;
      case MilestoneOwner.personB:
        return nameB;
      case MilestoneOwner.both:
        return '共同';
    }
  }
}

class MilestoneEvent {
  MilestoneEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.owner,
    required this.images,
  });

  final String id;
  final String title;
  final String description;
  final DateTime date;
  final MilestoneOwner owner;
  final List<String> images;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'date': date.toIso8601String(),
    'owner': owner.index,
    'images': images,
  };

  factory MilestoneEvent.fromJson(Map<String, dynamic> json) => MilestoneEvent(
    id:
        json['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString(),
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    date: DateTime.parse(json['date']),
    owner: MilestoneOwner.values[json['owner']],
    images: List<String>.from(json['images']),
  );
}

class MilestoneHomePage extends StatefulWidget {
  const MilestoneHomePage({super.key});

  @override
  State<MilestoneHomePage> createState() => _MilestoneHomePageState();
}

class _MilestoneHomePageState extends State<MilestoneHomePage> {
  String _personAName = '皓';
  String _personBName = '晴';
  double _scaleFactor = 1.0;
  double _baseScaleFactor = 1.0;
  List<MilestoneEvent> _events = [];

  @override
  void initState() {
    super.initState();
    _loadData().then((_) => _syncFromServer());
  }

  Future<void> _syncFromServer() async {
    final String serverUrl = Platform.isAndroid
        ? 'http://8.145.33.28:3000/api/milestones'
        : 'http://8.145.33.28:3000/api/milestones';

    try {
      final response = await http.get(Uri.parse(serverUrl));
      if (response.statusCode == 200) {
        final List<dynamic> serverJsonList = json.decode(response.body);
        final serverEvents = serverJsonList
            .map((j) => MilestoneEvent.fromJson(j))
            .toList();

        bool hasNew = false;
        final List<MilestoneEvent> updatedEvents = List.from(_events);

        for (var sEvent in serverEvents) {
          bool exists = updatedEvents.any(
            (localEvent) => localEvent.id == sEvent.id,
          );

          if (!exists) {
            updatedEvents.add(sEvent);
            hasNew = true;
          }
        }

        if (hasNew) {
          setState(() {
            _events = updatedEvents;
            _events.sort((a, b) => a.date.compareTo(b.date));
          });
          await _saveData();
        }
      }
    } catch (e) {
      debugPrint('Sync from server failed: $e');
    }
  }

  Future<void> _deleteEvent(MilestoneEvent event) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除提醒'),
        content: Text('确认要删除“${event.title}”吗？此操作将同时同步至服务器。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 1. 本地删除
    setState(() {
      _events.removeWhere((e) => e.id == event.id);
    });
    await _saveData();

    // 2. 服务器同步删除
    final String baseUrl = Platform.isAndroid
        ? 'http://8.145.33.28:3000/api/milestones'
        : 'http://8.145.33.28:3000/api/milestones';

    try {
      final response = await http.delete(Uri.parse('$baseUrl/${event.id}'));
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已成功从本地和服务器删除')));
        }
      } else {
        debugPrint('Server delete failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Network error during delete: $e');
    }
  }

  Future<void> _loadData() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(p.join(directory.path, 'milestones.json'));
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        setState(() {
          _events = jsonList.map((j) => MilestoneEvent.fromJson(j)).toList();
          _events.sort((a, b) => a.date.compareTo(b.date));
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
  }

  Future<void> _saveData() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(p.join(directory.path, 'milestones.json'));
      final jsonString = json.encode(_events.map((e) => e.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
      debugPrint('Error saving data: $e');
    }
  }

  Future<List<String>> _uploadToServer(
    MilestoneEvent event,
    List<XFile> imageFiles,
  ) async {
    // 💡 提示：Android 模拟器使用 10.0.2.2，iOS 模拟器使用 localhost
    // 如果是真机测试，请确保手机和电脑在同一个 WiFi，并使用电脑的局域网 IP (如 192.168.1.5)
    final String serverUrl = Platform.isAndroid
        ? 'http://8.145.33.28:3000/api/milestones'
        : 'http://8.145.33.28:3000/api/milestones';

    // Save images to local persistent storage as well
    final List<String> localPaths = [];
    try {
      final directory = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(directory.path, 'milestone_images'));
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      for (var xFile in imageFiles) {
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${p.basename(xFile.path)}';
        final savedFile = await File(
          xFile.path,
        ).copy(p.join(imagesDir.path, fileName));
        localPaths.add(savedFile.path);
      }
    } catch (e) {
      debugPrint('Error saving images locally: $e');
    }

    try {
      var request = http.MultipartRequest('POST', Uri.parse(serverUrl));

      // Add JSON data
      request.fields['event'] = json.encode(event.toJson());

      // Add multiple images
      for (var i = 0; i < imageFiles.length; i++) {
        var multipartFile = await http.MultipartFile.fromPath(
          'images',
          imageFiles[i].path,
          filename: p.basename(imageFiles[i].path),
        );
        request.files.add(multipartFile);
      }

      var response = await request.send();
      if (response.statusCode == 200 || response.statusCode == 201) {
        final respStr = await response.stream.bytesToString();
        final decoded = json.decode(respStr);
        // Assuming server returns the list of uploaded image URLs
        return List<String>.from(decoded['imageUrls'] ?? []);
      } else {
        debugPrint('Upload failed with status: ${response.statusCode}');
        return localPaths; // Fallback to local paths on upload failure
      }
    } catch (e) {
      debugPrint('Error uploading to server: $e');
      return localPaths; // Fallback to local paths on error
    }
  }

  void _openEditNamesDialog() {
    final aController = TextEditingController(text: _personAName);
    final bController = TextEditingController(text: _personBName);
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('修改称呼'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: aController,
                decoration: const InputDecoration(labelText: 'TA 的名字'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bController,
                decoration: const InputDecoration(labelText: '你 的名字'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _personAName = aController.text.trim().isEmpty
                      ? _personAName
                      : aController.text.trim();
                  _personBName = bController.text.trim().isEmpty
                      ? _personBName
                      : bController.text.trim();
                });
                Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAddEventDialog() async {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    MilestoneOwner owner = MilestoneOwner.both;
    final List<XFile> selectedImages = [];
    final ImagePicker picker = ImagePicker();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('添加里程碑'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: '标题'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(labelText: '描述'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<MilestoneOwner>(
                      value: owner,
                      items: MilestoneOwner.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                value.getLabel(_personAName, _personBName),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setLocalState(() => owner = value);
                      },
                      decoration: const InputDecoration(labelText: '节点类型'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '日期：${_formatDate(selectedDate)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setLocalState(() => selectedDate = picked);
                            }
                          },
                          child: const Text('选择日期'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('图片：'),
                        IconButton(
                          icon: const Icon(Icons.add_a_photo),
                          onPressed: () async {
                            final List<XFile> images = await picker
                                .pickMultiImage();
                            if (images.isNotEmpty) {
                              setLocalState(() {
                                selectedImages.addAll(images);
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    if (selectedImages.isNotEmpty)
                      SizedBox(
                        height: 60,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: selectedImages.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            return Stack(
                              children: [
                                Image.file(
                                  File(selectedImages[index].path),
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      setLocalState(() {
                                        selectedImages.removeAt(index);
                                      });
                                    },
                                    child: Container(
                                      color: Colors.black54,
                                      child: const Icon(
                                        Icons.close,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;

                    // Show loading
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) =>
                          const Center(child: CircularProgressIndicator()),
                    );

                    final tempEvent = MilestoneEvent(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: title,
                      description: descController.text.trim(),
                      date: selectedDate,
                      owner: owner,
                      images: [], // Initially empty
                    );

                    // Upload to server and get list of URLs (or local paths as fallback)
                    final List<String> imageUrls = await _uploadToServer(
                      tempEvent,
                      selectedImages,
                    );

                    setState(() {
                      _events.add(
                        MilestoneEvent(
                          id: tempEvent.id,
                          title: title,
                          description: tempEvent.description,
                          date: selectedDate,
                          owner: owner,
                          images: imageUrls,
                        ),
                      );
                      _events.sort((a, b) => a.date.compareTo(b.date));
                      _saveData(); // Persistent local storage
                    });

                    // Pop loading and dialog
                    if (mounted) {
                      Navigator.pop(context); // Pop loading
                      Navigator.pop(context); // Pop dialog
                    }
                  },
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupedEvents = _groupEventsByDate(_events);
    final dates = groupedEvents.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('情侣里程碑'),
        actions: [
          IconButton(
            tooltip: '缩小',
            onPressed: () {
              setState(() {
                _scaleFactor = (_scaleFactor / 1.2).clamp(0.01, 5.0);
              });
            },
            icon: const Icon(Icons.zoom_out),
          ),
          IconButton(
            tooltip: '放大',
            onPressed: () {
              setState(() {
                _scaleFactor = (_scaleFactor * 1.2).clamp(0.01, 5.0);
              });
            },
            icon: const Icon(Icons.zoom_in),
          ),
          IconButton(
            tooltip: '重置缩放',
            onPressed: () {
              setState(() {
                _scaleFactor = 1.0;
              });
            },
            icon: const Icon(Icons.restore),
          ),
          IconButton(
            tooltip: '修改称呼',
            onPressed: _openEditNamesDialog,
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddEventDialog,
        icon: const Icon(Icons.add),
        label: const Text('添加里程碑'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: _PersonLabel(
                    name: _personAName,
                    alignRight: true,
                    color: Colors.blue,
                  ),
                ),
                Expanded(
                  child: _PersonLabel(
                    name: _personBName,
                    alignRight: false,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableHeight = constraints.maxHeight;
                final dateSectionHeight = TimelineColumn.dateRowHeight + 12;
                final bodyHeight = (availableHeight - dateSectionHeight).clamp(
                  0.0,
                  double.infinity,
                );
                final lineTotal =
                    (TimelineColumn.lineRowHeight * 2) +
                    (TimelineColumn.gapHeight * 2);
                final slotsArea = (bodyHeight - lineTotal).clamp(
                  0.0,
                  double.infinity,
                );
                final topSlotHeight = slotsArea * 0.3;
                final middleSlotHeight = slotsArea * 0.4;
                final bottomSlotHeight = slotsArea * 0.3;

                final startDate = dates.isEmpty ? DateTime.now() : dates.first;
                final endDate = dates.isEmpty ? startDate : dates.last;
                final totalDays = endDate.difference(startDate).inDays;

                int minGapDays = 1;
                if (dates.length > 1) {
                  minGapDays = dates
                      .asMap()
                      .entries
                      .skip(1)
                      .map(
                        (entry) =>
                            entry.value.difference(dates[entry.key - 1]).inDays,
                      )
                      .where((days) => days > 0)
                      .fold<int>(
                        999999,
                        (min, days) => days < min ? days : min,
                      );
                  if (minGapDays == 999999) {
                    minGapDays = 1;
                  }
                }

                final minSpacing = TimelineColumn.columnWidth + 16;
                final pixelsPerDay =
                    (totalDays == 0 ? 0.0 : minSpacing / minGapDays) *
                    _scaleFactor;

                final contentWidth = totalDays == 0
                    ? TimelineColumn.columnWidth
                    : (totalDays * pixelsPerDay) + TimelineColumn.columnWidth;
                final minWidth = contentWidth < constraints.maxWidth
                    ? constraints.maxWidth
                    : contentWidth;

                return GestureDetector(
                  onScaleStart: (details) {
                    _baseScaleFactor = _scaleFactor;
                  },
                  onScaleUpdate: (details) {
                    setState(() {
                      _scaleFactor =
                          (_baseScaleFactor * details.horizontalScale).clamp(
                            0.01,
                            5.0,
                          );
                    });
                  },
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: minWidth),
                        child: SizedBox(
                          width: minWidth,
                          height: constraints.maxHeight,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _TimelineBackgroundPainter(
                                    topColor: Colors.blue,
                                    bottomColor: Colors.green,
                                    topLineY:
                                        dateSectionHeight +
                                        topSlotHeight +
                                        (TimelineColumn.lineRowHeight / 2),
                                    bottomLineY:
                                        dateSectionHeight +
                                        topSlotHeight +
                                        TimelineColumn.lineRowHeight +
                                        TimelineColumn.gapHeight +
                                        middleSlotHeight +
                                        TimelineColumn.gapHeight +
                                        (TimelineColumn.lineRowHeight / 2),
                                    middleY:
                                        dateSectionHeight +
                                        topSlotHeight +
                                        TimelineColumn.lineRowHeight +
                                        TimelineColumn.gapHeight +
                                        (middleSlotHeight / 2),
                                    dates: dates,
                                    groupedEvents: groupedEvents,
                                    startDate: startDate,
                                    pixelsPerDay: pixelsPerDay,
                                    columnWidth: TimelineColumn.columnWidth,
                                  ),
                                ),
                              ),
                              for (var i = 0; i < dates.length; i++)
                                Positioned(
                                  left: totalDays == 0
                                      ? 0
                                      : dates[i].difference(startDate).inDays *
                                            pixelsPerDay,
                                  top: 0,
                                  child: SizedBox(
                                    width: TimelineColumn.columnWidth,
                                    height: constraints.maxHeight,
                                    child: TimelineColumn(
                                      date: dates[i],
                                      events: groupedEvents[dates[i]] ?? [],
                                      personAName: _personAName,
                                      personBName: _personBName,
                                      topSlotHeight: topSlotHeight,
                                      middleSlotHeight: middleSlotHeight,
                                      bottomSlotHeight: bottomSlotHeight,
                                      onDelete: _deleteEvent,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonLabel extends StatelessWidget {
  const _PersonLabel({
    required this.name,
    required this.alignRight,
    required this.color,
  });

  final String name;
  final bool alignRight;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Text(
          name,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color.withOpacity(0.8),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class TimelineColumn extends StatelessWidget {
  const TimelineColumn({
    super.key,
    required this.date,
    required this.events,
    required this.personAName,
    required this.personBName,
    required this.topSlotHeight,
    required this.middleSlotHeight,
    required this.bottomSlotHeight,
    required this.onDelete,
  });

  final DateTime date;
  final List<MilestoneEvent> events;
  final String personAName;
  final String personBName;
  final double topSlotHeight;
  final double middleSlotHeight;
  final double bottomSlotHeight;
  final Function(MilestoneEvent) onDelete;

  static const double columnWidth = 240;
  static const double lineRowHeight = 24;
  static const double gapHeight = 12;
  static const double dateRowHeight = 24;

  @override
  Widget build(BuildContext context) {
    final aEvents = events
        .where((event) => event.owner == MilestoneOwner.personA)
        .toList();
    final bEvents = events
        .where((event) => event.owner == MilestoneOwner.personB)
        .toList();
    final bothEvents = events
        .where((event) => event.owner == MilestoneOwner.both)
        .toList();
    final showTopDot = aEvents.isNotEmpty || bothEvents.isNotEmpty;
    final showBottomDot = bEvents.isNotEmpty || bothEvents.isNotEmpty;
    final bool isBoth = bothEvents.isNotEmpty;

    final double topLineY = topSlotHeight + (lineRowHeight / 2);
    final double bottomLineY =
        topSlotHeight +
        lineRowHeight +
        gapHeight +
        middleSlotHeight +
        gapHeight +
        (lineRowHeight / 2);
    final double middleY =
        topSlotHeight + lineRowHeight + gapHeight + (middleSlotHeight / 2);

    double getPointY(bool shared, bool isTop) {
      final baseY = isTop ? topLineY : bottomLineY;
      if (!shared) return baseY;
      return baseY + (middleY - baseY) * 0.4;
    }

    final bodyHeight =
        topSlotHeight +
        lineRowHeight +
        gapHeight +
        middleSlotHeight +
        gapHeight +
        lineRowHeight +
        bottomSlotHeight;

    return SizedBox(
      width: columnWidth,
      child: Column(
        children: [
          // Remove the top fixed date row and replace with empty space to keep layout alignment
          const SizedBox(height: dateRowHeight + 12),
          SizedBox(
            height: bodyHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TimelineConnectorPainter(
                      topColor: Colors.blue,
                      bottomColor: Colors.green,
                      bothColor: Colors.pinkAccent,
                      showTopDot: showTopDot,
                      showBottomDot: showBottomDot,
                      hasBoth: isBoth,
                      topLineY: topLineY,
                      bottomLineY: bottomLineY,
                      middleY: middleY,
                    ),
                  ),
                ),
                // Date Labels
                if (isBoth) ...[
                  // Top date for shared event
                  Positioned(
                    top: getPointY(true, true) + 5,
                    left: 0,
                    right: 0,
                    child: _DateChip(date: date, color: Colors.pinkAccent),
                  ),
                  // Bottom date for shared event
                  Positioned(
                    top: getPointY(true, false) - 25,
                    left: 0,
                    right: 0,
                    child: _DateChip(date: date, color: Colors.pinkAccent),
                  ),
                ] else
                  // Single date for personal event
                  Positioned(
                    top: aEvents.isNotEmpty
                        ? getPointY(false, true) + 5
                        : getPointY(false, false) - 25,
                    left: 0,
                    right: 0,
                    child: _DateChip(
                      date: date,
                      color: aEvents.isNotEmpty ? Colors.blue : Colors.orange,
                    ),
                  ),
                Column(
                  children: [
                    SizedBox(
                      height: topSlotHeight,
                      child: ClipRect(
                        child: SingleChildScrollView(
                          reverse: true,
                          physics: const BouncingScrollPhysics(),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: _EventStack(
                              events: aEvents,
                              label: personAName,
                              onDelete: onDelete,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: lineRowHeight),
                    const SizedBox(height: gapHeight),
                    SizedBox(
                      height: middleSlotHeight,
                      child: Center(
                        child: ClipRect(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: _EventStack(
                              events: bothEvents,
                              label: '$personAName & $personBName',
                              compact: true,
                              onDelete: onDelete,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: gapHeight),
                    SizedBox(height: lineRowHeight),
                    SizedBox(
                      height: bottomSlotHeight,
                      child: ClipRect(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: _EventStack(
                              events: bEvents,
                              label: personBName,
                              onDelete: onDelete,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.date, required this.color});
  final DateTime date;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.85),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Text(
          _formatDate(date),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _TimelineBackgroundPainter extends CustomPainter {
  _TimelineBackgroundPainter({
    required this.topColor,
    required this.bottomColor,
    required this.topLineY,
    required this.bottomLineY,
    required this.middleY,
    required this.dates,
    required this.groupedEvents,
    required this.startDate,
    required this.pixelsPerDay,
    required this.columnWidth,
  });

  final Color topColor;
  final Color bottomColor;
  final double topLineY;
  final double bottomLineY;
  final double middleY;
  final List<DateTime> dates;
  final Map<DateTime, List<MilestoneEvent>> groupedEvents;
  final DateTime startDate;
  final double pixelsPerDay;
  final double columnWidth;

  bool _isShared(DateTime date) {
    return groupedEvents[date]?.any((e) => e.owner == MilestoneOwner.both) ??
        false;
  }

  double _getPointY(bool shared, bool isTop) {
    final baseY = isTop ? topLineY : bottomLineY;
    if (!shared) return baseY;
    // Converge 40% towards the middle
    return baseY + (middleY - baseY) * 0.4;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (dates.isEmpty) return;

    final topPaint = Paint()
      ..color = topColor.withOpacity(0.35)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final bottomPaint = Paint()
      ..color = bottomColor.withOpacity(0.35)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final topPath = Path();
    final bottomPath = Path();

    // Start from left edge
    final firstShared = _isShared(dates.first);
    double lastTopY = _getPointY(firstShared, true);
    double lastBottomY = _getPointY(firstShared, false);
    double lastX = 0;

    topPath.moveTo(lastX, lastTopY);
    bottomPath.moveTo(lastX, lastBottomY);

    for (var i = 0; i < dates.length; i++) {
      final date = dates[i];
      final centerX =
          (date.difference(startDate).inDays * pixelsPerDay) +
          (columnWidth / 2);
      final shared = _isShared(date);
      final targetTopY = _getPointY(shared, true);
      final targetBottomY = _getPointY(shared, false);

      // Draw smooth curve from lastX to centerX
      if (centerX > lastX) {
        final midX = lastX + (centerX - lastX) / 2;
        topPath.cubicTo(midX, lastTopY, midX, targetTopY, centerX, targetTopY);
        bottomPath.cubicTo(
          midX,
          lastBottomY,
          midX,
          targetBottomY,
          centerX,
          targetBottomY,
        );
      }

      lastX = centerX;
      lastTopY = targetTopY;
      lastBottomY = targetBottomY;
    }

    // End at right edge
    if (size.width > lastX) {
      final midX = lastX + (size.width - lastX) / 2;
      final endShared = _isShared(dates.last);
      final endTopY = _getPointY(endShared, true);
      final endBottomY = _getPointY(endShared, false);

      topPath.cubicTo(midX, lastTopY, midX, endTopY, size.width, endTopY);
      bottomPath.cubicTo(
        midX,
        lastBottomY,
        midX,
        endBottomY,
        size.width,
        endBottomY,
      );
    }

    canvas.drawPath(topPath, topPaint);
    canvas.drawPath(bottomPath, bottomPaint);
  }

  @override
  bool shouldRepaint(covariant _TimelineBackgroundPainter oldDelegate) {
    return true;
  }
}

class _TimelineConnectorPainter extends CustomPainter {
  _TimelineConnectorPainter({
    required this.topColor,
    required this.bottomColor,
    required this.bothColor,
    required this.showTopDot,
    required this.showBottomDot,
    required this.hasBoth,
    required this.topLineY,
    required this.bottomLineY,
    required this.middleY,
  });

  final Color topColor;
  final Color bottomColor;
  final Color bothColor;
  final bool showTopDot;
  final bool showBottomDot;
  final bool hasBoth;
  final double topLineY;
  final double bottomLineY;
  final double middleY;

  double _getPointY(bool shared, bool isTop) {
    final baseY = isTop ? topLineY : bottomLineY;
    if (!shared) return baseY;
    return baseY + (middleY - baseY) * 0.4;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;

    if (showTopDot) {
      final dotPaint = Paint()
        ..color = hasBoth ? bothColor : topColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(centerX, _getPointY(hasBoth, true)),
        6,
        dotPaint,
      );
    }

    if (showBottomDot) {
      final dotPaint = Paint()
        ..color = hasBoth ? bothColor : bottomColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(centerX, _getPointY(hasBoth, false)),
        6,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineConnectorPainter oldDelegate) {
    return true;
  }
}

class _EventStack extends StatelessWidget {
  const _EventStack({
    required this.events,
    required this.label,
    required this.onDelete,
    this.compact = false,
  });

  final List<MilestoneEvent> events;
  final String label;
  final bool compact;
  final Function(MilestoneEvent) onDelete;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < events.length; i++) ...[
          EventCard(
            event: events[i],
            label: label,
            compact: compact,
            onDelete: () => onDelete(events[i]),
          ),
          if (i != events.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class EventCard extends StatefulWidget {
  const EventCard({
    super.key,
    required this.event,
    required this.label,
    required this.onDelete,
    this.compact = false,
  });

  final MilestoneEvent event;
  final String label;
  final bool compact;
  final VoidCallback onDelete;

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final (bgColor, accentColor) = switch (widget.event.owner) {
      MilestoneOwner.personA => (
        Colors.blue.shade100.withOpacity(0.9),
        Colors.blue,
      ),
      MilestoneOwner.personB => (
        Colors.green.shade100.withOpacity(0.9),
        Colors.green,
      ),
      MilestoneOwner.both => (
        Colors.pink.shade50.withOpacity(0.9),
        Colors.pinkAccent,
      ),
    };

    final card = GestureDetector(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: bgColor.withOpacity(
            widget.event.owner == MilestoneOwner.both ? 0.6 : 0.85,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accentColor.withOpacity(_isExpanded ? 0.5 : 0.2),
            width: _isExpanded ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: EdgeInsets.all(widget.compact ? 8 : 12),
        margin: EdgeInsets.symmetric(
          horizontal: widget.event.owner == MilestoneOwner.both && !_isExpanded
              ? 48 // Extra margin for shared events to stay between lines
              : 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: textTheme.labelSmall?.copyWith(
                      color: accentColor.withOpacity(0.8),
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 12,
                  color: accentColor.withOpacity(0.5),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: widget.onDelete,
                  child: Icon(
                    Icons.delete_outline,
                    size: 14,
                    color: Colors.red.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              widget.event.title,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              maxLines: _isExpanded ? 3 : 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_isExpanded) ...[
              if (widget.event.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(widget.event.description, style: textTheme.bodySmall),
              ],
              if (widget.event.images.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      final url = widget.event.images[index];
                      Widget image;
                      if (url.startsWith('assets/')) {
                        image = Image.asset(
                          url,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        );
                      } else if (url.startsWith('http')) {
                        image = Image.network(
                          url,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        );
                      } else {
                        image = Image.file(
                          File(url),
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        );
                      }

                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: image,
                      );
                    },
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemCount: widget.event.images.length,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );

    if (widget.event.owner == MilestoneOwner.both) {
      // For shared events, we place them in the middle of the convergence area.
      // We don't want them to obscure the lines perfectly, so we make them a bit narrower
      // and ensure they are exactly in the center gap.
      return card;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.event.owner == MilestoneOwner.personB)
          CustomPaint(
            size: const Size(12, 6),
            painter: _BubbleTailPainter(color: bgColor, pointingDown: false),
          ),
        card,
        if (widget.event.owner == MilestoneOwner.personA)
          CustomPaint(
            size: const Size(12, 6),
            painter: _BubbleTailPainter(color: bgColor, pointingDown: true),
          ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool pointingDown;

  _BubbleTailPainter({required this.color, required this.pointingDown});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    if (pointingDown) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
    } else {
      path.moveTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _formatDate(DateTime date) {
  return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
}

Map<DateTime, List<MilestoneEvent>> _groupEventsByDate(
  List<MilestoneEvent> events,
) {
  final Map<DateTime, List<MilestoneEvent>> grouped = {};
  for (final event in events) {
    final key = DateTime(event.date.year, event.date.month, event.date.day);
    grouped.putIfAbsent(key, () => []).add(event);
  }
  return grouped;
}
