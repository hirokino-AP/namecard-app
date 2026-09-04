// lib/models/business_card.dart
// Phase 2対応版 - SQLite + Firebase Auth + プロジェクトコード連携

class BusinessCard {
  final int? id;
  final String userId;
  final String name;
  final String nameKana;
  final String company;
  final String companyKana;
  final String department;
  final String title;
  final String email;
  final String phone;
  final String mobilePhone;
  final String fax;
  final String zipCode;
  final String address;
  final String note;
  final String? imagePath;
  final String? voiceMemoPath;
  final List<String> projectCodes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BusinessCard({
    this.id,
    required this.userId,
    required this.name,
    required this.nameKana,
    required this.company,
    required this.companyKana,
    required this.department,
    required this.title,
    required this.email,
    required this.phone,
    required this.mobilePhone,
    required this.fax,
    required this.zipCode,
    required this.address,
    required this.note,
    this.imagePath,
    this.voiceMemoPath,
    required this.projectCodes,
    required this.createdAt,
    required this.updatedAt,
  });

  static List<String> _parseCodes(String? csv) {
    if (csv == null || csv.trim().isEmpty) return [];
    return csv.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static String _encodeCodes(List<String> codes) => codes.join(',');

  factory BusinessCard.fromMap(Map<String, dynamic> map) {
    return BusinessCard(
      id:           map['id'] as int?,
      userId:       map['user_id']        as String? ?? '',
      name:         map['name']           as String? ?? '',
      nameKana:     map['name_kana']      as String? ?? '',
      company:      map['company']        as String? ?? '',
      companyKana:  map['company_kana']   as String? ?? '',
      department:   map['department']     as String? ?? '',
      title:        map['title']          as String? ?? '',
      email:        map['email']          as String? ?? '',
      phone:        map['phone']          as String? ?? '',
      mobilePhone:  map['mobile_phone']   as String? ?? '',
      fax:          map['fax']            as String? ?? '',
      zipCode:      map['zip_code']       as String? ?? '',
      address:      map['address']        as String? ?? '',
      note:         map['note']           as String? ?? '',
      imagePath:    map['image_path']     as String?,
      voiceMemoPath:map['voice_memo_path'] as String?,
      projectCodes: _parseCodes(map['project_codes'] as String?),
      createdAt:    DateTime.parse(map['created_at'] as String),
      updatedAt:    DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'user_id':         userId,
      'name':            name,
      'name_kana':       nameKana,
      'company':         company,
      'company_kana':    companyKana,
      'department':      department,
      'title':           title,
      'email':           email,
      'phone':           phone,
      'mobile_phone':    mobilePhone,
      'fax':             fax,
      'zip_code':        zipCode,
      'address':         address,
      'note':            note,
      'image_path':      imagePath,
      'voice_memo_path': voiceMemoPath,
      'project_codes':   _encodeCodes(projectCodes),
      'created_at':      createdAt.toIso8601String(),
      'updated_at':      updatedAt.toIso8601String(),
    };
  }

  BusinessCard copyWith({
    int? id, String? userId, String? name, String? nameKana,
    String? company, String? companyKana, String? department,
    String? title, String? email, String? phone, String? mobilePhone,
    String? fax, String? zipCode, String? address, String? note,
    String? imagePath, String? voiceMemoPath, List<String>? projectCodes,
    DateTime? createdAt, DateTime? updatedAt,
  }) {
    return BusinessCard(
      id:            id            ?? this.id,
      userId:        userId        ?? this.userId,
      name:          name          ?? this.name,
      nameKana:      nameKana      ?? this.nameKana,
      company:       company       ?? this.company,
      companyKana:   companyKana   ?? this.companyKana,
      department:    department    ?? this.department,
      title:         title         ?? this.title,
      email:         email         ?? this.email,
      phone:         phone         ?? this.phone,
      mobilePhone:   mobilePhone   ?? this.mobilePhone,
      fax:           fax           ?? this.fax,
      zipCode:       zipCode       ?? this.zipCode,
      address:       address       ?? this.address,
      note:          note          ?? this.note,
      imagePath:     imagePath     ?? this.imagePath,
      voiceMemoPath: voiceMemoPath ?? this.voiceMemoPath,
      projectCodes:  projectCodes  ?? this.projectCodes,
      createdAt:     createdAt     ?? this.createdAt,
      updatedAt:     updatedAt     ?? this.updatedAt,
    );
  }

  factory BusinessCard.create({
    required String userId, required String name,
    String nameKana='', String company='', String companyKana='',
    String department='', String title='', String email='',
    String phone='', String mobilePhone='', String fax='',
    String zipCode='', String address='', String note='',
    String? imagePath, String? voiceMemoPath,
    List<String> projectCodes = const [],
  }) {
    final now = DateTime.now();
    return BusinessCard(
      userId:userId, name:name, nameKana:nameKana, company:company,
      companyKana:companyKana, department:department, title:title,
      email:email, phone:phone, mobilePhone:mobilePhone, fax:fax,
      zipCode:zipCode, address:address, note:note, imagePath:imagePath,
      voiceMemoPath:voiceMemoPath, projectCodes:projectCodes,
      createdAt:now, updatedAt:now,
    );
  }

  bool hasProject(String code) => projectCodes.contains(code);
  BusinessCard addProject(String code) {
    if (hasProject(code)) return this;
    return copyWith(projectCodes: [...projectCodes, code]);
  }
  BusinessCard removeProject(String code) =>
      copyWith(projectCodes: projectCodes.where((c) => c != code).toList());

  @override
  String toString() => 'BusinessCard(id:$id, name:$name, company:$company)';
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is BusinessCard && other.id == id);
  @override
  int get hashCode => id.hashCode;
}
