// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_metadata.dart';

// **************************************************************************
// _IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, invalid_use_of_protected_member, lines_longer_than_80_chars, constant_identifier_names, avoid_js_rounded_ints, no_leading_underscores_for_local_identifiers, require_trailing_commas, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_in_if_null_operators, library_private_types_in_public_api, prefer_const_constructors
// ignore_for_file: type=lint

extension GetFileMetadataCollection on Isar {
  IsarCollection<int, FileMetadata> get fileMetadatas => this.collection();
}

const FileMetadataSchema = IsarGeneratedSchema(
  schema: IsarSchema(
    name: 'FileMetadata',
    idName: 'id',
    embedded: false,
    properties: [
      IsarPropertySchema(
        name: 'path',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'name',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'extension',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'size',
        type: IsarType.long,
      ),
      IsarPropertySchema(
        name: 'lastModified',
        type: IsarType.dateTime,
      ),
      IsarPropertySchema(
        name: 'addedAt',
        type: IsarType.dateTime,
      ),
      IsarPropertySchema(
        name: 'extractedText',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'tags',
        type: IsarType.stringList,
      ),
      IsarPropertySchema(
        name: 'isIndexed',
        type: IsarType.bool,
      ),
      IsarPropertySchema(
        name: 'readableSize',
        type: IsarType.string,
      ),
    ],
    indexes: [
      IsarIndexSchema(
        name: 'path',
        properties: [
          "path",
        ],
        unique: false,
        hash: false,
      ),
      IsarIndexSchema(
        name: 'name',
        properties: [
          "name",
        ],
        unique: false,
        hash: false,
      ),
      IsarIndexSchema(
        name: 'extension',
        properties: [
          "extension",
        ],
        unique: false,
        hash: false,
      ),
      IsarIndexSchema(
        name: 'lastModified',
        properties: [
          "lastModified",
        ],
        unique: false,
        hash: false,
      ),
      IsarIndexSchema(
        name: 'extractedText',
        properties: [
          "extractedText",
        ],
        unique: false,
        hash: false,
      ),
    ],
  ),
  converter: IsarObjectConverter<int, FileMetadata>(
    serialize: serializeFileMetadata,
    deserialize: deserializeFileMetadata,
    deserializeProperty: deserializeFileMetadataProp,
  ),
  embeddedSchemas: [],
);

@isarProtected
int serializeFileMetadata(IsarWriter writer, FileMetadata object) {
  IsarCore.writeString(writer, 1, object.path);
  IsarCore.writeString(writer, 2, object.name);
  IsarCore.writeString(writer, 3, object.extension);
  IsarCore.writeLong(writer, 4, object.size);
  IsarCore.writeLong(
      writer, 5, object.lastModified.toUtc().microsecondsSinceEpoch);
  IsarCore.writeLong(writer, 6, object.addedAt.toUtc().microsecondsSinceEpoch);
  {
    final value = object.extractedText;
    if (value == null) {
      IsarCore.writeNull(writer, 7);
    } else {
      IsarCore.writeString(writer, 7, value);
    }
  }
  {
    final list = object.tags;
    if (list == null) {
      IsarCore.writeNull(writer, 8);
    } else {
      final listWriter = IsarCore.beginList(writer, 8, list.length);
      for (var i = 0; i < list.length; i++) {
        IsarCore.writeString(listWriter, i, list[i]);
      }
      IsarCore.endList(writer, listWriter);
    }
  }
  IsarCore.writeBool(writer, 9, object.isIndexed);
  IsarCore.writeString(writer, 10, object.readableSize);
  return object.id;
}

@isarProtected
FileMetadata deserializeFileMetadata(IsarReader reader) {
  final object = FileMetadata();
  object.id = IsarCore.readId(reader);
  object.path = IsarCore.readString(reader, 1) ?? '';
  object.name = IsarCore.readString(reader, 2) ?? '';
  object.extension = IsarCore.readString(reader, 3) ?? '';
  object.size = IsarCore.readLong(reader, 4);
  {
    final value = IsarCore.readLong(reader, 5);
    if (value == -9223372036854775808) {
      object.lastModified =
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
    } else {
      object.lastModified =
          DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true).toLocal();
    }
  }
  {
    final value = IsarCore.readLong(reader, 6);
    if (value == -9223372036854775808) {
      object.addedAt =
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
    } else {
      object.addedAt =
          DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true).toLocal();
    }
  }
  object.extractedText = IsarCore.readString(reader, 7);
  {
    final length = IsarCore.readList(reader, 8, IsarCore.readerPtrPtr);
    {
      final reader = IsarCore.readerPtr;
      if (reader.isNull) {
        object.tags = null;
      } else {
        final list = List<String>.filled(length, '', growable: true);
        for (var i = 0; i < length; i++) {
          list[i] = IsarCore.readString(reader, i) ?? '';
        }
        IsarCore.freeReader(reader);
        object.tags = list;
      }
    }
  }
  object.isIndexed = IsarCore.readBool(reader, 9);
  return object;
}

@isarProtected
dynamic deserializeFileMetadataProp(IsarReader reader, int property) {
  switch (property) {
    case 0:
      return IsarCore.readId(reader);
    case 1:
      return IsarCore.readString(reader, 1) ?? '';
    case 2:
      return IsarCore.readString(reader, 2) ?? '';
    case 3:
      return IsarCore.readString(reader, 3) ?? '';
    case 4:
      return IsarCore.readLong(reader, 4);
    case 5:
      {
        final value = IsarCore.readLong(reader, 5);
        if (value == -9223372036854775808) {
          return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
        } else {
          return DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true)
              .toLocal();
        }
      }
    case 6:
      {
        final value = IsarCore.readLong(reader, 6);
        if (value == -9223372036854775808) {
          return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
        } else {
          return DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true)
              .toLocal();
        }
      }
    case 7:
      return IsarCore.readString(reader, 7);
    case 8:
      {
        final length = IsarCore.readList(reader, 8, IsarCore.readerPtrPtr);
        {
          final reader = IsarCore.readerPtr;
          if (reader.isNull) {
            return null;
          } else {
            final list = List<String>.filled(length, '', growable: true);
            for (var i = 0; i < length; i++) {
              list[i] = IsarCore.readString(reader, i) ?? '';
            }
            IsarCore.freeReader(reader);
            return list;
          }
        }
      }
    case 9:
      return IsarCore.readBool(reader, 9);
    case 10:
      return IsarCore.readString(reader, 10) ?? '';
    default:
      throw ArgumentError('Unknown property: $property');
  }
}

sealed class _FileMetadataUpdate {
  bool call({
    required int id,
    String? path,
    String? name,
    String? extension,
    int? size,
    DateTime? lastModified,
    DateTime? addedAt,
    String? extractedText,
    bool? isIndexed,
    String? readableSize,
  });
}

class _FileMetadataUpdateImpl implements _FileMetadataUpdate {
  const _FileMetadataUpdateImpl(this.collection);

  final IsarCollection<int, FileMetadata> collection;

  @override
  bool call({
    required int id,
    Object? path = ignore,
    Object? name = ignore,
    Object? extension = ignore,
    Object? size = ignore,
    Object? lastModified = ignore,
    Object? addedAt = ignore,
    Object? extractedText = ignore,
    Object? isIndexed = ignore,
    Object? readableSize = ignore,
  }) {
    return collection.updateProperties([
          id
        ], {
          if (path != ignore) 1: path as String?,
          if (name != ignore) 2: name as String?,
          if (extension != ignore) 3: extension as String?,
          if (size != ignore) 4: size as int?,
          if (lastModified != ignore) 5: lastModified as DateTime?,
          if (addedAt != ignore) 6: addedAt as DateTime?,
          if (extractedText != ignore) 7: extractedText as String?,
          if (isIndexed != ignore) 9: isIndexed as bool?,
          if (readableSize != ignore) 10: readableSize as String?,
        }) >
        0;
  }
}

sealed class _FileMetadataUpdateAll {
  int call({
    required List<int> id,
    String? path,
    String? name,
    String? extension,
    int? size,
    DateTime? lastModified,
    DateTime? addedAt,
    String? extractedText,
    bool? isIndexed,
    String? readableSize,
  });
}

class _FileMetadataUpdateAllImpl implements _FileMetadataUpdateAll {
  const _FileMetadataUpdateAllImpl(this.collection);

  final IsarCollection<int, FileMetadata> collection;

  @override
  int call({
    required List<int> id,
    Object? path = ignore,
    Object? name = ignore,
    Object? extension = ignore,
    Object? size = ignore,
    Object? lastModified = ignore,
    Object? addedAt = ignore,
    Object? extractedText = ignore,
    Object? isIndexed = ignore,
    Object? readableSize = ignore,
  }) {
    return collection.updateProperties(id, {
      if (path != ignore) 1: path as String?,
      if (name != ignore) 2: name as String?,
      if (extension != ignore) 3: extension as String?,
      if (size != ignore) 4: size as int?,
      if (lastModified != ignore) 5: lastModified as DateTime?,
      if (addedAt != ignore) 6: addedAt as DateTime?,
      if (extractedText != ignore) 7: extractedText as String?,
      if (isIndexed != ignore) 9: isIndexed as bool?,
      if (readableSize != ignore) 10: readableSize as String?,
    });
  }
}

extension FileMetadataUpdate on IsarCollection<int, FileMetadata> {
  _FileMetadataUpdate get update => _FileMetadataUpdateImpl(this);

  _FileMetadataUpdateAll get updateAll => _FileMetadataUpdateAllImpl(this);
}

sealed class _FileMetadataQueryUpdate {
  int call({
    String? path,
    String? name,
    String? extension,
    int? size,
    DateTime? lastModified,
    DateTime? addedAt,
    String? extractedText,
    bool? isIndexed,
    String? readableSize,
  });
}

class _FileMetadataQueryUpdateImpl implements _FileMetadataQueryUpdate {
  const _FileMetadataQueryUpdateImpl(this.query, {this.limit});

  final IsarQuery<FileMetadata> query;
  final int? limit;

  @override
  int call({
    Object? path = ignore,
    Object? name = ignore,
    Object? extension = ignore,
    Object? size = ignore,
    Object? lastModified = ignore,
    Object? addedAt = ignore,
    Object? extractedText = ignore,
    Object? isIndexed = ignore,
    Object? readableSize = ignore,
  }) {
    return query.updateProperties(limit: limit, {
      if (path != ignore) 1: path as String?,
      if (name != ignore) 2: name as String?,
      if (extension != ignore) 3: extension as String?,
      if (size != ignore) 4: size as int?,
      if (lastModified != ignore) 5: lastModified as DateTime?,
      if (addedAt != ignore) 6: addedAt as DateTime?,
      if (extractedText != ignore) 7: extractedText as String?,
      if (isIndexed != ignore) 9: isIndexed as bool?,
      if (readableSize != ignore) 10: readableSize as String?,
    });
  }
}

extension FileMetadataQueryUpdate on IsarQuery<FileMetadata> {
  _FileMetadataQueryUpdate get updateFirst =>
      _FileMetadataQueryUpdateImpl(this, limit: 1);

  _FileMetadataQueryUpdate get updateAll => _FileMetadataQueryUpdateImpl(this);
}

class _FileMetadataQueryBuilderUpdateImpl implements _FileMetadataQueryUpdate {
  const _FileMetadataQueryBuilderUpdateImpl(this.query, {this.limit});

  final QueryBuilder<FileMetadata, FileMetadata, QOperations> query;
  final int? limit;

  @override
  int call({
    Object? path = ignore,
    Object? name = ignore,
    Object? extension = ignore,
    Object? size = ignore,
    Object? lastModified = ignore,
    Object? addedAt = ignore,
    Object? extractedText = ignore,
    Object? isIndexed = ignore,
    Object? readableSize = ignore,
  }) {
    final q = query.build();
    try {
      return q.updateProperties(limit: limit, {
        if (path != ignore) 1: path as String?,
        if (name != ignore) 2: name as String?,
        if (extension != ignore) 3: extension as String?,
        if (size != ignore) 4: size as int?,
        if (lastModified != ignore) 5: lastModified as DateTime?,
        if (addedAt != ignore) 6: addedAt as DateTime?,
        if (extractedText != ignore) 7: extractedText as String?,
        if (isIndexed != ignore) 9: isIndexed as bool?,
        if (readableSize != ignore) 10: readableSize as String?,
      });
    } finally {
      q.close();
    }
  }
}

extension FileMetadataQueryBuilderUpdate
    on QueryBuilder<FileMetadata, FileMetadata, QOperations> {
  _FileMetadataQueryUpdate get updateFirst =>
      _FileMetadataQueryBuilderUpdateImpl(this, limit: 1);

  _FileMetadataQueryUpdate get updateAll =>
      _FileMetadataQueryBuilderUpdateImpl(this);
}

extension FileMetadataQueryFilter
    on QueryBuilder<FileMetadata, FileMetadata, QFilterCondition> {
  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> idEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> idGreaterThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      idGreaterThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> idLessThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      idLessThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> idBetween(
    int lower,
    int upper,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 0,
          lower: lower,
          upper: upper,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> pathEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      pathGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      pathGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> pathLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      pathLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> pathBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 1,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      pathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> pathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> pathContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> pathMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 1,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      pathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 1,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      pathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 1,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      nameGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      nameGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> nameLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      nameLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 2,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> nameContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> nameMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 2,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 2,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 2,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extensionEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extensionGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extensionGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extensionLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extensionLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extensionBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 3,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extensionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extensionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extensionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extensionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 3,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extensionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 3,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extensionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 3,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> sizeEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 4,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      sizeGreaterThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 4,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      sizeGreaterThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 4,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> sizeLessThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 4,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      sizeLessThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 4,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> sizeBetween(
    int lower,
    int upper,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 4,
          lower: lower,
          upper: upper,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      lastModifiedEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 5,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      lastModifiedGreaterThan(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 5,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      lastModifiedGreaterThanOrEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 5,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      lastModifiedLessThan(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 5,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      lastModifiedLessThanOrEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 5,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      lastModifiedBetween(
    DateTime lower,
    DateTime upper,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 5,
          lower: lower,
          upper: upper,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      addedAtEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 6,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      addedAtGreaterThan(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 6,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      addedAtGreaterThanOrEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 6,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      addedAtLessThan(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 6,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      addedAtLessThanOrEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 6,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      addedAtBetween(
    DateTime lower,
    DateTime upper,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 6,
          lower: lower,
          upper: upper,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const IsNullCondition(property: 7));
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextIsNotNull() {
    return QueryBuilder.apply(not(), (query) {
      return query.addFilterCondition(const IsNullCondition(property: 7));
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 7,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextGreaterThan(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 7,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextGreaterThanOrEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 7,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextLessThan(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 7,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextLessThanOrEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 7,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextBetween(
    String? lower,
    String? upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 7,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 7,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 7,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 7,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 7,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 7,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      extractedTextIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 7,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition> tagsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const IsNullCondition(property: 8));
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsIsNotNull() {
    return QueryBuilder.apply(not(), (query) {
      return query.addFilterCondition(const IsNullCondition(property: 8));
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 8,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsElementGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 8,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsElementGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 8,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsElementLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 8,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsElementLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 8,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsElementBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 8,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 8,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 8,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 8,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 8,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 8,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 8,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsIsEmpty() {
    return not().group(
      (q) => q.tagsIsNull().or().tagsIsNotEmpty(),
    );
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      tagsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterOrEqualCondition(property: 8, value: null),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      isIndexedEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 9,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      readableSizeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 10,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      readableSizeGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 10,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      readableSizeGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 10,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      readableSizeLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 10,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      readableSizeLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 10,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      readableSizeBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 10,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      readableSizeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 10,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      readableSizeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 10,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      readableSizeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 10,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      readableSizeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 10,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      readableSizeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 10,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterFilterCondition>
      readableSizeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 10,
          value: '',
        ),
      );
    });
  }
}

extension FileMetadataQueryObject
    on QueryBuilder<FileMetadata, FileMetadata, QFilterCondition> {}

extension FileMetadataQuerySortBy
    on QueryBuilder<FileMetadata, FileMetadata, QSortBy> {
  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0, sort: Sort.desc);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByPath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        1,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByPathDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        1,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        2,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByNameDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        2,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByExtension(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        3,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByExtensionDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        3,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortBySize() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(4);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortBySizeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(4, sort: Sort.desc);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByLastModified() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(5);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy>
      sortByLastModifiedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(5, sort: Sort.desc);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByAddedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(6);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByAddedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(6, sort: Sort.desc);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByExtractedText(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        7,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy>
      sortByExtractedTextDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        7,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByIsIndexed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(9);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByIsIndexedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(9, sort: Sort.desc);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByReadableSize(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        10,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> sortByReadableSizeDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        10,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }
}

extension FileMetadataQuerySortThenBy
    on QueryBuilder<FileMetadata, FileMetadata, QSortThenBy> {
  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0, sort: Sort.desc);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByPath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(1, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByPathDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(1, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(2, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByNameDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(2, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByExtension(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(3, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByExtensionDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(3, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenBySize() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(4);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenBySizeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(4, sort: Sort.desc);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByLastModified() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(5);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy>
      thenByLastModifiedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(5, sort: Sort.desc);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByAddedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(6);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByAddedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(6, sort: Sort.desc);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByExtractedText(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy>
      thenByExtractedTextDesc({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByIsIndexed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(9);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByIsIndexedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(9, sort: Sort.desc);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByReadableSize(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(10, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterSortBy> thenByReadableSizeDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(10, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }
}

extension FileMetadataQueryWhereDistinct
    on QueryBuilder<FileMetadata, FileMetadata, QDistinct> {
  QueryBuilder<FileMetadata, FileMetadata, QAfterDistinct> distinctByPath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(1, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(2, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterDistinct> distinctByExtension(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(3, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterDistinct> distinctBySize() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(4);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterDistinct>
      distinctByLastModified() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(5);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterDistinct> distinctByAddedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(6);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterDistinct>
      distinctByExtractedText({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(7, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterDistinct> distinctByTags() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(8);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterDistinct>
      distinctByIsIndexed() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(9);
    });
  }

  QueryBuilder<FileMetadata, FileMetadata, QAfterDistinct>
      distinctByReadableSize({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(10, caseSensitive: caseSensitive);
    });
  }
}

extension FileMetadataQueryProperty1
    on QueryBuilder<FileMetadata, FileMetadata, QProperty> {
  QueryBuilder<FileMetadata, int, QAfterProperty> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }

  QueryBuilder<FileMetadata, String, QAfterProperty> pathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<FileMetadata, String, QAfterProperty> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<FileMetadata, String, QAfterProperty> extensionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }

  QueryBuilder<FileMetadata, int, QAfterProperty> sizeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(4);
    });
  }

  QueryBuilder<FileMetadata, DateTime, QAfterProperty> lastModifiedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(5);
    });
  }

  QueryBuilder<FileMetadata, DateTime, QAfterProperty> addedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(6);
    });
  }

  QueryBuilder<FileMetadata, String?, QAfterProperty> extractedTextProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(7);
    });
  }

  QueryBuilder<FileMetadata, List<String>?, QAfterProperty> tagsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(8);
    });
  }

  QueryBuilder<FileMetadata, bool, QAfterProperty> isIndexedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(9);
    });
  }

  QueryBuilder<FileMetadata, String, QAfterProperty> readableSizeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(10);
    });
  }
}

extension FileMetadataQueryProperty2<R>
    on QueryBuilder<FileMetadata, R, QAfterProperty> {
  QueryBuilder<FileMetadata, (R, int), QAfterProperty> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }

  QueryBuilder<FileMetadata, (R, String), QAfterProperty> pathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<FileMetadata, (R, String), QAfterProperty> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<FileMetadata, (R, String), QAfterProperty> extensionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }

  QueryBuilder<FileMetadata, (R, int), QAfterProperty> sizeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(4);
    });
  }

  QueryBuilder<FileMetadata, (R, DateTime), QAfterProperty>
      lastModifiedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(5);
    });
  }

  QueryBuilder<FileMetadata, (R, DateTime), QAfterProperty> addedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(6);
    });
  }

  QueryBuilder<FileMetadata, (R, String?), QAfterProperty>
      extractedTextProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(7);
    });
  }

  QueryBuilder<FileMetadata, (R, List<String>?), QAfterProperty>
      tagsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(8);
    });
  }

  QueryBuilder<FileMetadata, (R, bool), QAfterProperty> isIndexedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(9);
    });
  }

  QueryBuilder<FileMetadata, (R, String), QAfterProperty>
      readableSizeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(10);
    });
  }
}

extension FileMetadataQueryProperty3<R1, R2>
    on QueryBuilder<FileMetadata, (R1, R2), QAfterProperty> {
  QueryBuilder<FileMetadata, (R1, R2, int), QOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }

  QueryBuilder<FileMetadata, (R1, R2, String), QOperations> pathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<FileMetadata, (R1, R2, String), QOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<FileMetadata, (R1, R2, String), QOperations>
      extensionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }

  QueryBuilder<FileMetadata, (R1, R2, int), QOperations> sizeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(4);
    });
  }

  QueryBuilder<FileMetadata, (R1, R2, DateTime), QOperations>
      lastModifiedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(5);
    });
  }

  QueryBuilder<FileMetadata, (R1, R2, DateTime), QOperations>
      addedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(6);
    });
  }

  QueryBuilder<FileMetadata, (R1, R2, String?), QOperations>
      extractedTextProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(7);
    });
  }

  QueryBuilder<FileMetadata, (R1, R2, List<String>?), QOperations>
      tagsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(8);
    });
  }

  QueryBuilder<FileMetadata, (R1, R2, bool), QOperations> isIndexedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(9);
    });
  }

  QueryBuilder<FileMetadata, (R1, R2, String), QOperations>
      readableSizeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(10);
    });
  }
}
