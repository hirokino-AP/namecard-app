// ============================================================
// lib/services/excel_service.dart
//
// 【役割】
//   名刺データをExcel形式で出力し、ShareSheetで共有する。
//   ユーザーはShareSheetからOutlookを選択してメール送信できる。
//
// 【処理フロー】
//   1. 全名刺データを取得
//   2. Excelファイルを生成（ヘッダー行＋データ行）
//   3. 一時ファイルに保存
//   4. ShareSheetで共有
// ============================================================

import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/business_card.dart';

class ExcelService {
  // Excelのヘッダー行定義
  static const List<String> _headers = [
    '氏名', 'よみがな', '会社名', '会社名かな', '部署', '役職', '業種',
    'メール', '電話', '携帯', 'FAX', '郵便番号', '住所', '備考',
    'プロジェクトコード', '登録日', '更新日',
  ];

  // 名刺データをExcelファイルに出力してShareSheetで共有
  static Future<void> exportAndShare(List<BusinessCard> cards) async {
    // Excelファイル生成

    final excel = Excel.createExcel();
    final sheet = excel['名刺データ'];

    // デフォルトシートを削除
    excel.delete('Sheet1');

    // ヘッダー行を追加（太字・背景色あり）
    for (int i = 0; i < _headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(_headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#185FA5'), // Navy Blue
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      );
    }

    // データ行を追加
    for (int i = 0; i < cards.length; i++) {
      final card = cards[i];
      final rowIndex = i + 1;
      final values = [
        card.name,
        card.nameKana,
        card.company,
        card.companyKana,
        card.department,
        card.title,
        card.industry,
        card.email,
        card.phone,
        card.mobilePhone,

        card.fax,
        card.zipCode,
        card.address,
        card.note,
        card.projectCodes.join(','),
        card.createdAt.toIso8601String().substring(0, 10),
        card.updatedAt.toIso8601String().substring(0, 10),
      ];

      for (int j = 0; j < values.length; j++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: rowIndex));
        cell.value = TextCellValue(values[j]);
      }
    }

    // 列幅を自動調整
    sheet.setColumnWidth(0, 15);  // 氏名
    sheet.setColumnWidth(1, 15);  // よみがな
    sheet.setColumnWidth(2, 25);  // 会社名
    sheet.setColumnWidth(3, 25);  // 会社名かな
    sheet.setColumnWidth(4, 20);  // 部署
    sheet.setColumnWidth(5, 15);  // 役職
    sheet.setColumnWidth(6, 20);  // 業種
    sheet.setColumnWidth(7, 30);  // メール
    sheet.setColumnWidth(8, 15);  // 電話
    sheet.setColumnWidth(9, 15);  // 携帯
    sheet.setColumnWidth(10, 15); // FAX
    sheet.setColumnWidth(11, 12); // 郵便番号
    sheet.setColumnWidth(12, 40); // 住所

    // 一時ファイルに保存
    final tmpDir = await getTemporaryDirectory();

    final now = DateTime.now();
    final fileName = '名刺データ_${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}.xlsx';
    final filePath = '${tmpDir.path}/$fileName';
    final fileBytes = excel.encode();
    if (fileBytes == null) throw Exception('Excelファイルの生成に失敗しました');
    await File(filePath).writeAsBytes(fileBytes);

    // ShareSheetで共有（Outlookなどから送信可能）
    final xFile = XFile(
      filePath,
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [xFile],
        subject: '名刺データ_$fileName',
        text: '名刺データ（${cards.length}件）を添付します。',
      ),
    );
  }
}
