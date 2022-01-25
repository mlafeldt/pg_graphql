create table graphql._type (
    id serial primary key,
    type_kind graphql.type_kind not null,
    meta_kind graphql.meta_kind not null,
    is_builtin bool not null default false,
    constant_name text,
    name text not null,
    entity regclass,
    graphql_type_id int references graphql._type(id),
    enum regtype,
    description text,
    unique (meta_kind, entity),
    check (entity is null or graphql_type_id is null)
);

create index ix_graphql_type_name on graphql._type(name);


create or replace function graphql.inflect_type_default(text)
    returns text
    language sql
    immutable
as $$
    select replace(initcap($1), '_', '');
$$;


create function graphql.type_name(rec graphql._type)
    returns text
    immutable
    language sql
as $$
    with name_override as (
        select
            case
                when rec.entity is not null then coalesce(
                    graphql.comment_directive_name(rec.entity),
                    graphql.inflect_type_default(graphql.to_table_name(rec.entity))
                )
                else null
            end as base_type_name
    )
    select
        case
            when (rec).is_builtin then rec.meta_kind::text
            when rec.meta_kind='Node'         then base_type_name
            when rec.meta_kind='Edge'         then format('%sEdge',       base_type_name)
            when rec.meta_kind='Connection'   then format('%sConnection', base_type_name)
            when rec.meta_kind='OrderBy'      then format('%sOrderBy',    base_type_name)
            when rec.meta_kind='FilterEntity' then format('%sFilter',     base_type_name)
            when rec.meta_kind='FilterType'   then format('%sFilter',     graphql.type_name(rec.graphql_type_id))
            when rec.meta_kind='OrderByDirection' then rec.meta_kind::text
            when rec.meta_kind='PageInfo'     then rec.meta_kind::text
            when rec.meta_kind='Cursor'       then rec.meta_kind::text
            when rec.meta_kind='Query'        then rec.meta_kind::text
            when rec.meta_kind='Mutation'     then rec.meta_kind::text
            when rec.meta_kind='Enum'         then coalesce(
                graphql.comment_directive_name(rec.enum),
                graphql.inflect_type_default(graphql.to_type_name(rec.enum))
            )
            else graphql.exception('could not determine type name')
        end
    from
        name_override
$$;

create function graphql.type_name(type_id int)
    returns text
    immutable
    language sql
as $$
    select
        graphql.type_name(rec)
    from
        graphql._type rec
    where
        id = $1;
$$;


create function graphql.set_type_name()
    returns trigger
    language plpgsql
as $$
begin
    new.name = coalesce(
        new.constant_name,
        graphql.type_name(new)
    );
    return new;
end;
$$;

create trigger on_insert_set_name
    before insert on graphql._type
    for each row execute procedure graphql.set_type_name();
