import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ActivityPage(),
    );
  }
}

class ActivityPage extends StatefulWidget {
  const ActivityPage({Key? key}) : super(key: key);

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  late CalendarFormat _calendarFormat;
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  List<Event> _events = [];

  @override
  void initState() {
    super.initState();
    _calendarFormat = CalendarFormat.month;
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
    _loadEvents();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Page'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () {
              _showCalendar();
            },
          ),
        ],
      ),
      body: Center(
        child: const Text('Activity Page'),
      ),
    );
  }

  void _showCalendar() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          height: 400,
          child: TableCalendar(
            calendarFormat: _calendarFormat,
            focusedDay: _focusedDay,
            firstDay: DateTime.utc(2022, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                shape: BoxShape.circle,
              ),
            ),
            headerStyle: HeaderStyle(
              titleTextStyle: TextStyle(fontSize: 20),
              formatButtonShowsNext: false,
            ),
            eventLoader: (day) => _getEvents(day),
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
                _showEventDialog();
              });
            },
          ),
        );
      },
    );
  }

  List<Event> _getEvents(DateTime day) {
    return _events.where((event) => isSameDay(event.date, day)).toList();
  }

  void _loadEvents() async {
    final QuerySnapshot<Map<String, dynamic>> querySnapshot =
    await FirebaseFirestore.instance.collection('events').get();

    _events = querySnapshot.docs
        .map((doc) =>
        Event(doc['title'], DateTime.fromMillisecondsSinceEpoch(
          doc['date'].millisecondsSinceEpoch,
          isUtc: true,
        )))
        .toList();

    setState(() {});
  }

  void _showEventDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return _buildEventDialog();
      },
    );
  }

  Widget _buildEventDialog() {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _getUserSnapshot(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          DocumentSnapshot<Map<String, dynamic>> userSnapshot = snapshot.data!;
          String profileType = userSnapshot.data()?['profileType'];

          List<Event> eventsForSelectedDay = _getEvents(_selectedDay);

          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eventsForSelectedDay.isNotEmpty)
                  Column(
                    children: eventsForSelectedDay
                        .map((event) => _buildEventItem(event, profileType))
                        .toList(),
                  )
                else
                  Text('No events for this day'),

                if (profileType == 'Admin') // Only admins can add events
                  TextField(
                    decoration: const InputDecoration(labelText: 'New Event'),
                    onSubmitted: (value) {
                      _addEvent(value);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              if (profileType == 'Admin') // Only admins can add events
                TextButton(
                  onPressed: () {
                    // You can add additional logic here if needed
                    Navigator.pop(context);
                  },
                  child: const Text('OK'),
                ),
            ],
          );
        }
      },
    );
  }
  Widget _buildEventItem(Event event, String profileType) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(event.title),
        if (profileType == 'Admin') // Only admins can delete events
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: () {
              _deleteEvent(event);
            },
          ),
      ],
    );
  }
  void _deleteEvent(Event event) async {
    String userUid = FirebaseAuth.instance.currentUser!.uid;
    DocumentSnapshot<Map<String, dynamic>> userSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userUid)
        .get();

    String profileType = userSnapshot.data()?['profileType'];

    if (profileType == 'Admin') {
      // Remove the event from the list
      _events.remove(event);

      // Remove the event from Firestore
      await FirebaseFirestore.instance.collection('events').doc(event.id).delete();

      setState(() {});

      // Notify the user that the event has been deleted
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Event deleted successfully.'),
        ),
      );
    } else {
      // Non-admin users are not allowed to delete events
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Only users with admin profile can delete events.'),
        ),
      );
    }
  }


  Future<DocumentSnapshot<Map<String, dynamic>>> _getUserSnapshot() async {
    String userUid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('users').doc(userUid).get();
  }



  void _addEvent(String title) async {
    // Check the user's profile type before allowing to add an event
    String userUid = FirebaseAuth.instance.currentUser!.uid;
    DocumentSnapshot<Map<String, dynamic>> userSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userUid)
        .get();

    String profileType = userSnapshot.data()?['profileType'];

    if (profileType == 'Admin') {
      final newEvent = Event(title, _selectedDay);

      // Add the new event to the local list
      setState(() {
        _events.add(newEvent);
      });

      // Add the new event to Firestore
      await FirebaseFirestore.instance.collection('events').add({
        'title': newEvent.title,
        'date': newEvent.date.toUtc(),
        'addedBy': userUid, // Optional: Store who added the event
      });

      // Notify the user that the event has been added
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Event added successfully.'),
        ),
      );
    } else {
      // Non-admin users are not allowed to add events
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Only users with admin profile can add events.'),
        ),
      );
    }
  }




}

class Event {
  final String? id; // Make id nullable
  final String title;
  final DateTime date;

  Event(this.title, this.date, {this.id}); // Make id an optional named parameter

  // Add a factory constructor to create an event from a DocumentSnapshot
  factory Event.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    return Event(
      snapshot['title'],
      DateTime.fromMillisecondsSinceEpoch(
        snapshot['date'].millisecondsSinceEpoch,
        isUtc: true,
      ),
      id: snapshot.id, // Assign the document id as the event id
    );
  }
}

