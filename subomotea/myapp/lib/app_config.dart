import 'package:flutter/material.dart';

// Colors
// ---------------------------------------------------------------------------
const Color kBlue = Color(0xFF2563EB);
const Color kGreen = Color(0xFF2E7D32);
const Color kBackground = Color(0xFFF3F4F6);
const Color kLightBlue = Color(0xFFE8F0FE);
const String kSupabaseUrl = 'https://zxlmsbscrngqcdcnwxtq.supabase.co';
const String kSupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp4bG1zYnNjcm5ncWNkY253eHRxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMwMDA0MTUsImV4cCI6MjEwODU3NjQxNX0.LtTbTCFvJagw7xClTqyF3KVDMFZkw5CzQOOzv5Jqc1s';
String? kSupabaseStartupError;

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

/// Formats a number as Philippine pesos, e.g. 1234.5 -> ₱1,234.50
String peso(double value) {
  final negative = value < 0;
  final parts = value.abs().toStringAsFixed(2).split('.');
  final intPart = parts[0];
  final buffer = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
    buffer.write(intPart[i]);
  }
  return '${negative ? '-' : ''}₱${buffer.toString()}.${parts[1]}';
}

const List<String> _weekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];
const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}, ${d.year}';

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

double roundMoney(double v) => (v * 100).round() / 100;

// ---------------------------------------------------------------------------
