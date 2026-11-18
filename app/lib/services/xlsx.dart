import 'dart:convert';
import 'package:archive/archive.dart';
import '../models/entities.dart';

List<int> callsWorkbook(
  String employeeId,
  String employee,
  List<CallEntry> calls,
  Lead? Function(String) leadFor,
) {
  String xml(Object? value) => (value?.toString() ?? '')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  final sorted = calls.toList()..sort((a, b) => b.at.compareTo(a.at));
  final rows = <List<Object>>[
    [
      'Employee ID',
      'Employee',
      'Lead',
      'Phone',
      'Call date',
      'Call time',
      'Direction',
      'Duration seconds',
      'Outcome',
      'Note',
      'Source',
    ],
    ...sorted.map((c) {
      final l = leadFor(c.leadId);
      final t = c.at.toLocal();
      return <Object>[
        employeeId,
        employee,
        l?.name ?? '',
        l?.phone ?? '',
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}',
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}',
        c.direction,
        c.seconds,
        c.outcome,
        c.note,
        c.source,
      ];
    }),
  ];
  final sheet = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="11" width="23" customWidth="1"/></cols><sheetData>',
  );
  for (var i = 0; i < rows.length; i++) {
    sheet.write('<row r="${i + 1}">');
    for (var j = 0; j < rows[i].length; j++) {
      final v = rows[i][j];
      final ref = '${String.fromCharCode(65 + j)}${i + 1}';
      sheet.write(
        v is int
            ? '<c r="$ref"><v>$v</v></c>'
            : '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${xml(v)}</t></is></c>',
      );
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData><autoFilter ref="A1:K${rows.length}"/></worksheet>');
  final files = <String, String>{
    '[Content_Types].xml':
        '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>',
    '_rels/.rels':
        '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml':
        '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Call report" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
    'xl/worksheets/sheet1.xml': sheet.toString(),
  };
  final archive = Archive();
  files.forEach((name, data) {
    final bytes = utf8.encode(data);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(archive);
}
