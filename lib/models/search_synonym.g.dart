// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_synonym.dart';

// **************************************************************************
// _IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, invalid_use_of_protected_member, lines_longer_than_80_chars, constant_identifier_names, avoid_js_rounded_ints, no_leading_underscores_for_local_identifiers, require_trailing_commas, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_in_if_null_operators, library_private_types_in_public_api, prefer_const_constructors
// ignore_for_file: type=lint

extension GetSearchSynonymCollection on Isar {
  IsarCollection<int, SearchSynonym> get searchSynonyms => this.collection();
}

const SearchSynonymSchema = IsarGeneratedSchema(
  schema: IsarSchema(
    name: 'SearchSynonym',
    idName: 'id',
    embedded: false,
    properties: [
      IsarPropertySchema(
        name: 'term',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'expansions',
        type: IsarType.stringList,
      ),
      IsarPropertySchema(
        name: 'category',
        type: IsarType.string,
      ),
    ],
    indexes: [
      IsarIndexSchema(
        name: 'term',
        properties: [
          "term",
        ],
        unique: true,
        hash: false,
      ),
    ],
  ),
  converter: IsarObjectConverter<int, SearchSynonym>(
    serialize: serializeSearchSynonym,
    deserialize: deserializeSearchSynonym,
    deserializeProperty: deserializeSearchSynonymProp,
  ),
  embeddedSchemas: [],
);

@isarProtected
int serializeSearchSynonym(IsarWriter writer, SearchSynonym object) {
  IsarCore.writeString(writer, 1, object.term);
  {
    final list = object.expansions;
    final listWriter = IsarCore.beginList(writer, 2, list.length);
    for (var i = 0; i < list.length; i++) {
      IsarCore.writeString(listWriter, i, list[i]);
    }
    IsarCore.endList(writer, listWriter);
  }
  IsarCore.writeString(writer, 3, object.category);
  return object.id;
}

@isarProtected
SearchSynonym deserializeSearchSynonym(IsarReader reader) {
  final object = SearchSynonym();
  object.id = IsarCore.readId(reader);
  object.term = IsarCore.readString(reader, 1) ?? '';
  {
    final length = IsarCore.readList(reader, 2, IsarCore.readerPtrPtr);
    {
      final reader = IsarCore.readerPtr;
      if (reader.isNull) {
        object.expansions = const <String>[];
      } else {
        final list = List<String>.filled(length, '', growable: true);
        for (var i = 0; i < length; i++) {
          list[i] = IsarCore.readString(reader, i) ?? '';
        }
        IsarCore.freeReader(reader);
        object.expansions = list;
      }
    }
  }
  object.category = IsarCore.readString(reader, 3) ?? '';
  return object;
}

@isarProtected
dynamic deserializeSearchSynonymProp(IsarReader reader, int property) {
  switch (property) {
    case 0:
      return IsarCore.readId(reader);
    case 1:
      return IsarCore.readString(reader, 1) ?? '';
    case 2:
      {
        final length = IsarCore.readList(reader, 2, IsarCore.readerPtrPtr);
        {
          final reader = IsarCore.readerPtr;
          if (reader.isNull) {
            return const <String>[];
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
    case 3:
      return IsarCore.readString(reader, 3) ?? '';
    default:
      throw ArgumentError('Unknown property: $property');
  }
}

sealed class _SearchSynonymUpdate {
  bool call({
    required int id,
    String? term,
    String? category,
  });
}

class _SearchSynonymUpdateImpl implements _SearchSynonymUpdate {
  const _SearchSynonymUpdateImpl(this.collection);

  final IsarCollection<int, SearchSynonym> collection;

  @override
  bool call({
    required int id,
    Object? term = ignore,
    Object? category = ignore,
  }) {
    return collection.updateProperties([
          id
        ], {
          if (term != ignore) 1: term as String?,
          if (category != ignore) 3: category as String?,
        }) >
        0;
  }
}

sealed class _SearchSynonymUpdateAll {
  int call({
    required List<int> id,
    String? term,
    String? category,
  });
}

class _SearchSynonymUpdateAllImpl implements _SearchSynonymUpdateAll {
  const _SearchSynonymUpdateAllImpl(this.collection);

  final IsarCollection<int, SearchSynonym> collection;

  @override
  int call({
    required List<int> id,
    Object? term = ignore,
    Object? category = ignore,
  }) {
    return collection.updateProperties(id, {
      if (term != ignore) 1: term as String?,
      if (category != ignore) 3: category as String?,
    });
  }
}

extension SearchSynonymUpdate on IsarCollection<int, SearchSynonym> {
  _SearchSynonymUpdate get update => _SearchSynonymUpdateImpl(this);

  _SearchSynonymUpdateAll get updateAll => _SearchSynonymUpdateAllImpl(this);
}

sealed class _SearchSynonymQueryUpdate {
  int call({
    String? term,
    String? category,
  });
}

class _SearchSynonymQueryUpdateImpl implements _SearchSynonymQueryUpdate {
  const _SearchSynonymQueryUpdateImpl(this.query, {this.limit});

  final IsarQuery<SearchSynonym> query;
  final int? limit;

  @override
  int call({
    Object? term = ignore,
    Object? category = ignore,
  }) {
    return query.updateProperties(limit: limit, {
      if (term != ignore) 1: term as String?,
      if (category != ignore) 3: category as String?,
    });
  }
}

extension SearchSynonymQueryUpdate on IsarQuery<SearchSynonym> {
  _SearchSynonymQueryUpdate get updateFirst =>
      _SearchSynonymQueryUpdateImpl(this, limit: 1);

  _SearchSynonymQueryUpdate get updateAll =>
      _SearchSynonymQueryUpdateImpl(this);
}

class _SearchSynonymQueryBuilderUpdateImpl
    implements _SearchSynonymQueryUpdate {
  const _SearchSynonymQueryBuilderUpdateImpl(this.query, {this.limit});

  final QueryBuilder<SearchSynonym, SearchSynonym, QOperations> query;
  final int? limit;

  @override
  int call({
    Object? term = ignore,
    Object? category = ignore,
  }) {
    final q = query.build();
    try {
      return q.updateProperties(limit: limit, {
        if (term != ignore) 1: term as String?,
        if (category != ignore) 3: category as String?,
      });
    } finally {
      q.close();
    }
  }
}

extension SearchSynonymQueryBuilderUpdate
    on QueryBuilder<SearchSynonym, SearchSynonym, QOperations> {
  _SearchSynonymQueryUpdate get updateFirst =>
      _SearchSynonymQueryBuilderUpdateImpl(this, limit: 1);

  _SearchSynonymQueryUpdate get updateAll =>
      _SearchSynonymQueryBuilderUpdateImpl(this);
}

extension SearchSynonymQueryFilter
    on QueryBuilder<SearchSynonym, SearchSynonym, QFilterCondition> {
  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition> idEqualTo(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      idGreaterThan(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition> idBetween(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition> termEqualTo(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      termGreaterThan(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      termGreaterThanOrEqualTo(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      termLessThan(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      termLessThanOrEqualTo(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition> termBetween(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      termStartsWith(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      termEndsWith(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      termContains(String value, {bool caseSensitive = true}) {
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition> termMatches(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      termIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 1,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      termIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 1,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsElementEqualTo(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsElementGreaterThan(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsElementGreaterThanOrEqualTo(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsElementLessThan(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsElementLessThanOrEqualTo(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsElementBetween(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsElementStartsWith(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsElementEndsWith(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsElementContains(String value, {bool caseSensitive = true}) {
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsElementMatches(String pattern, {bool caseSensitive = true}) {
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 2,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 2,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsIsEmpty() {
    return not().expansionsIsNotEmpty();
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      expansionsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterOrEqualCondition(property: 2, value: null),
      );
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      categoryEqualTo(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      categoryGreaterThan(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      categoryGreaterThanOrEqualTo(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      categoryLessThan(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      categoryLessThanOrEqualTo(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      categoryBetween(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      categoryStartsWith(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      categoryEndsWith(
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      categoryContains(String value, {bool caseSensitive = true}) {
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      categoryMatches(String pattern, {bool caseSensitive = true}) {
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

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      categoryIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 3,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterFilterCondition>
      categoryIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 3,
          value: '',
        ),
      );
    });
  }
}

extension SearchSynonymQueryObject
    on QueryBuilder<SearchSynonym, SearchSynonym, QFilterCondition> {}

extension SearchSynonymQuerySortBy
    on QueryBuilder<SearchSynonym, SearchSynonym, QSortBy> {
  QueryBuilder<SearchSynonym, SearchSynonym, QAfterSortBy> sortById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0);
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterSortBy> sortByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0, sort: Sort.desc);
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterSortBy> sortByTerm(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        1,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterSortBy> sortByTermDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        1,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterSortBy> sortByCategory(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        3,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterSortBy> sortByCategoryDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        3,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }
}

extension SearchSynonymQuerySortThenBy
    on QueryBuilder<SearchSynonym, SearchSynonym, QSortThenBy> {
  QueryBuilder<SearchSynonym, SearchSynonym, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0);
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0, sort: Sort.desc);
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterSortBy> thenByTerm(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(1, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterSortBy> thenByTermDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(1, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterSortBy> thenByCategory(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(3, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterSortBy> thenByCategoryDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(3, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }
}

extension SearchSynonymQueryWhereDistinct
    on QueryBuilder<SearchSynonym, SearchSynonym, QDistinct> {
  QueryBuilder<SearchSynonym, SearchSynonym, QAfterDistinct> distinctByTerm(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(1, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterDistinct>
      distinctByExpansions() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(2);
    });
  }

  QueryBuilder<SearchSynonym, SearchSynonym, QAfterDistinct> distinctByCategory(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(3, caseSensitive: caseSensitive);
    });
  }
}

extension SearchSynonymQueryProperty1
    on QueryBuilder<SearchSynonym, SearchSynonym, QProperty> {
  QueryBuilder<SearchSynonym, int, QAfterProperty> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }

  QueryBuilder<SearchSynonym, String, QAfterProperty> termProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<SearchSynonym, List<String>, QAfterProperty>
      expansionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<SearchSynonym, String, QAfterProperty> categoryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }
}

extension SearchSynonymQueryProperty2<R>
    on QueryBuilder<SearchSynonym, R, QAfterProperty> {
  QueryBuilder<SearchSynonym, (R, int), QAfterProperty> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }

  QueryBuilder<SearchSynonym, (R, String), QAfterProperty> termProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<SearchSynonym, (R, List<String>), QAfterProperty>
      expansionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<SearchSynonym, (R, String), QAfterProperty> categoryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }
}

extension SearchSynonymQueryProperty3<R1, R2>
    on QueryBuilder<SearchSynonym, (R1, R2), QAfterProperty> {
  QueryBuilder<SearchSynonym, (R1, R2, int), QOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }

  QueryBuilder<SearchSynonym, (R1, R2, String), QOperations> termProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<SearchSynonym, (R1, R2, List<String>), QOperations>
      expansionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<SearchSynonym, (R1, R2, String), QOperations>
      categoryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }
}
