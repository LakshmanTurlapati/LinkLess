// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ConversationEntriesTable extends ConversationEntries
    with TableInfo<$ConversationEntriesTable, ConversationEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _audioFilePathMeta = const VerificationMeta(
    'audioFilePath',
  );
  @override
  late final GeneratedColumn<String> audioFilePath = GeneratedColumn<String>(
    'audio_file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    peerId,
    audioFilePath,
    latitude,
    longitude,
    startedAt,
    endedAt,
    durationSeconds,
    syncStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversation_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('audio_file_path')) {
      context.handle(
        _audioFilePathMeta,
        audioFilePath.isAcceptableOrUnknown(
          data['audio_file_path']!,
          _audioFilePathMeta,
        ),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConversationEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationEntry(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      peerId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}peer_id'],
          )!,
      audioFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_file_path'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      startedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}started_at'],
          )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      ),
      syncStatus:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}sync_status'],
          )!,
    );
  }

  @override
  $ConversationEntriesTable createAlias(String alias) {
    return $ConversationEntriesTable(attachedDatabase, alias);
  }
}

class ConversationEntry extends DataClass
    implements Insertable<ConversationEntry> {
  final String id;
  final String peerId;
  final String? audioFilePath;
  final double? latitude;
  final double? longitude;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final String syncStatus;
  const ConversationEntry({
    required this.id,
    required this.peerId,
    this.audioFilePath,
    this.latitude,
    this.longitude,
    required this.startedAt,
    this.endedAt,
    this.durationSeconds,
    required this.syncStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['peer_id'] = Variable<String>(peerId);
    if (!nullToAbsent || audioFilePath != null) {
      map['audio_file_path'] = Variable<String>(audioFilePath);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    if (!nullToAbsent || durationSeconds != null) {
      map['duration_seconds'] = Variable<int>(durationSeconds);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    return map;
  }

  ConversationEntriesCompanion toCompanion(bool nullToAbsent) {
    return ConversationEntriesCompanion(
      id: Value(id),
      peerId: Value(peerId),
      audioFilePath:
          audioFilePath == null && nullToAbsent
              ? const Value.absent()
              : Value(audioFilePath),
      latitude:
          latitude == null && nullToAbsent
              ? const Value.absent()
              : Value(latitude),
      longitude:
          longitude == null && nullToAbsent
              ? const Value.absent()
              : Value(longitude),
      startedAt: Value(startedAt),
      endedAt:
          endedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(endedAt),
      durationSeconds:
          durationSeconds == null && nullToAbsent
              ? const Value.absent()
              : Value(durationSeconds),
      syncStatus: Value(syncStatus),
    );
  }

  factory ConversationEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationEntry(
      id: serializer.fromJson<String>(json['id']),
      peerId: serializer.fromJson<String>(json['peerId']),
      audioFilePath: serializer.fromJson<String?>(json['audioFilePath']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      durationSeconds: serializer.fromJson<int?>(json['durationSeconds']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'peerId': serializer.toJson<String>(peerId),
      'audioFilePath': serializer.toJson<String?>(audioFilePath),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'durationSeconds': serializer.toJson<int?>(durationSeconds),
      'syncStatus': serializer.toJson<String>(syncStatus),
    };
  }

  ConversationEntry copyWith({
    String? id,
    String? peerId,
    Value<String?> audioFilePath = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
    Value<int?> durationSeconds = const Value.absent(),
    String? syncStatus,
  }) => ConversationEntry(
    id: id ?? this.id,
    peerId: peerId ?? this.peerId,
    audioFilePath:
        audioFilePath.present ? audioFilePath.value : this.audioFilePath,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    durationSeconds:
        durationSeconds.present ? durationSeconds.value : this.durationSeconds,
    syncStatus: syncStatus ?? this.syncStatus,
  );
  ConversationEntry copyWithCompanion(ConversationEntriesCompanion data) {
    return ConversationEntry(
      id: data.id.present ? data.id.value : this.id,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      audioFilePath:
          data.audioFilePath.present
              ? data.audioFilePath.value
              : this.audioFilePath,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      durationSeconds:
          data.durationSeconds.present
              ? data.durationSeconds.value
              : this.durationSeconds,
      syncStatus:
          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationEntry(')
          ..write('id: $id, ')
          ..write('peerId: $peerId, ')
          ..write('audioFilePath: $audioFilePath, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    peerId,
    audioFilePath,
    latitude,
    longitude,
    startedAt,
    endedAt,
    durationSeconds,
    syncStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationEntry &&
          other.id == this.id &&
          other.peerId == this.peerId &&
          other.audioFilePath == this.audioFilePath &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.durationSeconds == this.durationSeconds &&
          other.syncStatus == this.syncStatus);
}

class ConversationEntriesCompanion extends UpdateCompanion<ConversationEntry> {
  final Value<String> id;
  final Value<String> peerId;
  final Value<String?> audioFilePath;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<int?> durationSeconds;
  final Value<String> syncStatus;
  final Value<int> rowid;
  const ConversationEntriesCompanion({
    this.id = const Value.absent(),
    this.peerId = const Value.absent(),
    this.audioFilePath = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationEntriesCompanion.insert({
    required String id,
    required String peerId,
    this.audioFilePath = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       peerId = Value(peerId),
       startedAt = Value(startedAt);
  static Insertable<ConversationEntry> custom({
    Expression<String>? id,
    Expression<String>? peerId,
    Expression<String>? audioFilePath,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<int>? durationSeconds,
    Expression<String>? syncStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (peerId != null) 'peer_id': peerId,
      if (audioFilePath != null) 'audio_file_path': audioFilePath,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? peerId,
    Value<String?>? audioFilePath,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<int?>? durationSeconds,
    Value<String>? syncStatus,
    Value<int>? rowid,
  }) {
    return ConversationEntriesCompanion(
      id: id ?? this.id,
      peerId: peerId ?? this.peerId,
      audioFilePath: audioFilePath ?? this.audioFilePath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      syncStatus: syncStatus ?? this.syncStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (audioFilePath.present) {
      map['audio_file_path'] = Variable<String>(audioFilePath.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationEntriesCompanion(')
          ..write('id: $id, ')
          ..write('peerId: $peerId, ')
          ..write('audioFilePath: $audioFilePath, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BlockedUserEntriesTable extends BlockedUserEntries
    with TableInfo<$BlockedUserEntriesTable, BlockedUserEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlockedUserEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blockedUserIdMeta = const VerificationMeta(
    'blockedUserId',
  );
  @override
  late final GeneratedColumn<String> blockedUserId = GeneratedColumn<String>(
    'blocked_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blockedAtMeta = const VerificationMeta(
    'blockedAt',
  );
  @override
  late final GeneratedColumn<DateTime> blockedAt = GeneratedColumn<DateTime>(
    'blocked_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, blockedUserId, blockedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'blocked_user_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<BlockedUserEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('blocked_user_id')) {
      context.handle(
        _blockedUserIdMeta,
        blockedUserId.isAcceptableOrUnknown(
          data['blocked_user_id']!,
          _blockedUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_blockedUserIdMeta);
    }
    if (data.containsKey('blocked_at')) {
      context.handle(
        _blockedAtMeta,
        blockedAt.isAcceptableOrUnknown(data['blocked_at']!, _blockedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_blockedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BlockedUserEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BlockedUserEntry(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      blockedUserId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}blocked_user_id'],
          )!,
      blockedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}blocked_at'],
          )!,
    );
  }

  @override
  $BlockedUserEntriesTable createAlias(String alias) {
    return $BlockedUserEntriesTable(attachedDatabase, alias);
  }
}

class BlockedUserEntry extends DataClass
    implements Insertable<BlockedUserEntry> {
  /// Local row ID (UUID string).
  final String id;

  /// The blocked user's UUID.
  final String blockedUserId;

  /// When this user was blocked.
  final DateTime blockedAt;
  const BlockedUserEntry({
    required this.id,
    required this.blockedUserId,
    required this.blockedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['blocked_user_id'] = Variable<String>(blockedUserId);
    map['blocked_at'] = Variable<DateTime>(blockedAt);
    return map;
  }

  BlockedUserEntriesCompanion toCompanion(bool nullToAbsent) {
    return BlockedUserEntriesCompanion(
      id: Value(id),
      blockedUserId: Value(blockedUserId),
      blockedAt: Value(blockedAt),
    );
  }

  factory BlockedUserEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BlockedUserEntry(
      id: serializer.fromJson<String>(json['id']),
      blockedUserId: serializer.fromJson<String>(json['blockedUserId']),
      blockedAt: serializer.fromJson<DateTime>(json['blockedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'blockedUserId': serializer.toJson<String>(blockedUserId),
      'blockedAt': serializer.toJson<DateTime>(blockedAt),
    };
  }

  BlockedUserEntry copyWith({
    String? id,
    String? blockedUserId,
    DateTime? blockedAt,
  }) => BlockedUserEntry(
    id: id ?? this.id,
    blockedUserId: blockedUserId ?? this.blockedUserId,
    blockedAt: blockedAt ?? this.blockedAt,
  );
  BlockedUserEntry copyWithCompanion(BlockedUserEntriesCompanion data) {
    return BlockedUserEntry(
      id: data.id.present ? data.id.value : this.id,
      blockedUserId:
          data.blockedUserId.present
              ? data.blockedUserId.value
              : this.blockedUserId,
      blockedAt: data.blockedAt.present ? data.blockedAt.value : this.blockedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BlockedUserEntry(')
          ..write('id: $id, ')
          ..write('blockedUserId: $blockedUserId, ')
          ..write('blockedAt: $blockedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, blockedUserId, blockedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlockedUserEntry &&
          other.id == this.id &&
          other.blockedUserId == this.blockedUserId &&
          other.blockedAt == this.blockedAt);
}

class BlockedUserEntriesCompanion extends UpdateCompanion<BlockedUserEntry> {
  final Value<String> id;
  final Value<String> blockedUserId;
  final Value<DateTime> blockedAt;
  final Value<int> rowid;
  const BlockedUserEntriesCompanion({
    this.id = const Value.absent(),
    this.blockedUserId = const Value.absent(),
    this.blockedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BlockedUserEntriesCompanion.insert({
    required String id,
    required String blockedUserId,
    required DateTime blockedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       blockedUserId = Value(blockedUserId),
       blockedAt = Value(blockedAt);
  static Insertable<BlockedUserEntry> custom({
    Expression<String>? id,
    Expression<String>? blockedUserId,
    Expression<DateTime>? blockedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (blockedUserId != null) 'blocked_user_id': blockedUserId,
      if (blockedAt != null) 'blocked_at': blockedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BlockedUserEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? blockedUserId,
    Value<DateTime>? blockedAt,
    Value<int>? rowid,
  }) {
    return BlockedUserEntriesCompanion(
      id: id ?? this.id,
      blockedUserId: blockedUserId ?? this.blockedUserId,
      blockedAt: blockedAt ?? this.blockedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (blockedUserId.present) {
      map['blocked_user_id'] = Variable<String>(blockedUserId.value);
    }
    if (blockedAt.present) {
      map['blocked_at'] = Variable<DateTime>(blockedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BlockedUserEntriesCompanion(')
          ..write('id: $id, ')
          ..write('blockedUserId: $blockedUserId, ')
          ..write('blockedAt: $blockedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ConversationEntriesTable conversationEntries =
      $ConversationEntriesTable(this);
  late final $BlockedUserEntriesTable blockedUserEntries =
      $BlockedUserEntriesTable(this);
  late final ConversationDao conversationDao = ConversationDao(
    this as AppDatabase,
  );
  late final BlockedUsersDao blockedUsersDao = BlockedUsersDao(
    this as AppDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    conversationEntries,
    blockedUserEntries,
  ];
}

typedef $$ConversationEntriesTableCreateCompanionBuilder =
    ConversationEntriesCompanion Function({
      required String id,
      required String peerId,
      Value<String?> audioFilePath,
      Value<double?> latitude,
      Value<double?> longitude,
      required DateTime startedAt,
      Value<DateTime?> endedAt,
      Value<int?> durationSeconds,
      Value<String> syncStatus,
      Value<int> rowid,
    });
typedef $$ConversationEntriesTableUpdateCompanionBuilder =
    ConversationEntriesCompanion Function({
      Value<String> id,
      Value<String> peerId,
      Value<String?> audioFilePath,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<DateTime> startedAt,
      Value<DateTime?> endedAt,
      Value<int?> durationSeconds,
      Value<String> syncStatus,
      Value<int> rowid,
    });

class $$ConversationEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationEntriesTable> {
  $$ConversationEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioFilePath => $composableBuilder(
    column: $table.audioFilePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConversationEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationEntriesTable> {
  $$ConversationEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioFilePath => $composableBuilder(
    column: $table.audioFilePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationEntriesTable> {
  $$ConversationEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<String> get audioFilePath => $composableBuilder(
    column: $table.audioFilePath,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );
}

class $$ConversationEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationEntriesTable,
          ConversationEntry,
          $$ConversationEntriesTableFilterComposer,
          $$ConversationEntriesTableOrderingComposer,
          $$ConversationEntriesTableAnnotationComposer,
          $$ConversationEntriesTableCreateCompanionBuilder,
          $$ConversationEntriesTableUpdateCompanionBuilder,
          (
            ConversationEntry,
            BaseReferences<
              _$AppDatabase,
              $ConversationEntriesTable,
              ConversationEntry
            >,
          ),
          ConversationEntry,
          PrefetchHooks Function()
        > {
  $$ConversationEntriesTableTableManager(
    _$AppDatabase db,
    $ConversationEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$ConversationEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$ConversationEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$ConversationEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> peerId = const Value.absent(),
                Value<String?> audioFilePath = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationEntriesCompanion(
                id: id,
                peerId: peerId,
                audioFilePath: audioFilePath,
                latitude: latitude,
                longitude: longitude,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: durationSeconds,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String peerId,
                Value<String?> audioFilePath = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                required DateTime startedAt,
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationEntriesCompanion.insert(
                id: id,
                peerId: peerId,
                audioFilePath: audioFilePath,
                latitude: latitude,
                longitude: longitude,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: durationSeconds,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConversationEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationEntriesTable,
      ConversationEntry,
      $$ConversationEntriesTableFilterComposer,
      $$ConversationEntriesTableOrderingComposer,
      $$ConversationEntriesTableAnnotationComposer,
      $$ConversationEntriesTableCreateCompanionBuilder,
      $$ConversationEntriesTableUpdateCompanionBuilder,
      (
        ConversationEntry,
        BaseReferences<
          _$AppDatabase,
          $ConversationEntriesTable,
          ConversationEntry
        >,
      ),
      ConversationEntry,
      PrefetchHooks Function()
    >;
typedef $$BlockedUserEntriesTableCreateCompanionBuilder =
    BlockedUserEntriesCompanion Function({
      required String id,
      required String blockedUserId,
      required DateTime blockedAt,
      Value<int> rowid,
    });
typedef $$BlockedUserEntriesTableUpdateCompanionBuilder =
    BlockedUserEntriesCompanion Function({
      Value<String> id,
      Value<String> blockedUserId,
      Value<DateTime> blockedAt,
      Value<int> rowid,
    });

class $$BlockedUserEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $BlockedUserEntriesTable> {
  $$BlockedUserEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blockedUserId => $composableBuilder(
    column: $table.blockedUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get blockedAt => $composableBuilder(
    column: $table.blockedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BlockedUserEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $BlockedUserEntriesTable> {
  $$BlockedUserEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blockedUserId => $composableBuilder(
    column: $table.blockedUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get blockedAt => $composableBuilder(
    column: $table.blockedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BlockedUserEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BlockedUserEntriesTable> {
  $$BlockedUserEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get blockedUserId => $composableBuilder(
    column: $table.blockedUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get blockedAt =>
      $composableBuilder(column: $table.blockedAt, builder: (column) => column);
}

class $$BlockedUserEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BlockedUserEntriesTable,
          BlockedUserEntry,
          $$BlockedUserEntriesTableFilterComposer,
          $$BlockedUserEntriesTableOrderingComposer,
          $$BlockedUserEntriesTableAnnotationComposer,
          $$BlockedUserEntriesTableCreateCompanionBuilder,
          $$BlockedUserEntriesTableUpdateCompanionBuilder,
          (
            BlockedUserEntry,
            BaseReferences<
              _$AppDatabase,
              $BlockedUserEntriesTable,
              BlockedUserEntry
            >,
          ),
          BlockedUserEntry,
          PrefetchHooks Function()
        > {
  $$BlockedUserEntriesTableTableManager(
    _$AppDatabase db,
    $BlockedUserEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$BlockedUserEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$BlockedUserEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$BlockedUserEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> blockedUserId = const Value.absent(),
                Value<DateTime> blockedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BlockedUserEntriesCompanion(
                id: id,
                blockedUserId: blockedUserId,
                blockedAt: blockedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String blockedUserId,
                required DateTime blockedAt,
                Value<int> rowid = const Value.absent(),
              }) => BlockedUserEntriesCompanion.insert(
                id: id,
                blockedUserId: blockedUserId,
                blockedAt: blockedAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BlockedUserEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BlockedUserEntriesTable,
      BlockedUserEntry,
      $$BlockedUserEntriesTableFilterComposer,
      $$BlockedUserEntriesTableOrderingComposer,
      $$BlockedUserEntriesTableAnnotationComposer,
      $$BlockedUserEntriesTableCreateCompanionBuilder,
      $$BlockedUserEntriesTableUpdateCompanionBuilder,
      (
        BlockedUserEntry,
        BaseReferences<
          _$AppDatabase,
          $BlockedUserEntriesTable,
          BlockedUserEntry
        >,
      ),
      BlockedUserEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ConversationEntriesTableTableManager get conversationEntries =>
      $$ConversationEntriesTableTableManager(_db, _db.conversationEntries);
  $$BlockedUserEntriesTableTableManager get blockedUserEntries =>
      $$BlockedUserEntriesTableTableManager(_db, _db.blockedUserEntries);
}
