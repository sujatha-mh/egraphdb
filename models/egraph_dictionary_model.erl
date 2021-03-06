%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2018, Neeraj Sharma
%%% @doc
%%%
%%% @end
%%% %CopyrightBegin%
%%%
%%% Copyright Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in> 2017.
%%% All Rights Reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%
%%% %CopyrightEnd%
%%%-------------------------------------------------------------------
-module(egraph_dictionary_model).
%% -behaviour(egraph_callback).
-export([init/0, init/2, terminate/1, % CRUD
         validate/2, create/3, read/2, update/3, delete/2]).
-export([create/4, update/4]).
-export([read_resource/1]).
-export([read_all_resource/3]).
-export([read_max_resource/0]).
-export_type([egraph_k/0]).

-include("egraph_constants.hrl").

-type egraph_k() :: map().
-type state() :: term().

-define(LAGER_ATTRS, [{type, model}]).

%%%===================================================================
%%% API
%%%===================================================================

%%%===================================================================
%%% Callbacks
%%%===================================================================

%% @doc Initialize the state that the handler will carry for
%% a specific request throughout its progression. The state
%% is then passed on to each subsequent call to this model.
-spec init() -> state().
init() ->
    nostate.

init(_, QsProplist) ->
    [{proplist, QsProplist}].

%% @doc At the end of a request, the state is passed back in
%% to allow for clean up.
-spec terminate(state()) -> term().
terminate(_State) ->
    ok.

%% @doc Return, via a boolean value, whether the user-submitted
%% data structure is considered to be valid by this model's standard.
-spec validate(egraph_k() | term(), state()) -> {boolean(), state()}.
validate(V, State) ->
    {is_map(V) orelse is_list(V) orelse is_boolean(V), State}.

%% @doc Create a new entry. If the id is `undefined', the user
%% has not submitted an id under which to store the resource:
%% the id needs to be generated by the model, and (if successful),
%% returned via `{true, GeneratedId}'.
%% Otherwise, a given id will be passed, and a simple `true' or
%% `false' value may be returned to confirm the results.
%%
%% The created resource is validated before this function is called.
-spec create(egraph_callback:id() | undefined, egraph_k(), state()) ->
        {false | true | {true, egraph_callback:id()}, state()}.
create(undefined, V, State) ->
    create_info(V, State);
create(Key, V, State) ->
    Info2 = V#{<<"id">> => Key},
    create_info(Info2, State).

%% @doc Create a new entry along with an expiry of some seconds.
-spec create(egraph_callback:id() | undefined, egraph_k(),
             [{binary(), binary()}], state()) ->
    {false | true | {true, egraph_callback:id()}, state()}.
create(Key, V, _QsProplist, State) ->
    create(Key, V, State).

%% @doc Read a given entry from the store based on its Key.
-spec read(egraph_callback:id(), state()) ->
        { {ok, egraph_k()} |
          {function, Fun :: function()},
          {error, not_found}, state()}.
read(undefined, State) ->
    %% return everthing you have
    {{function, fun read_all_resource/3}, State};
read(Key, State) ->
    RawKey = egraph_util:convert_to_integer(Key),
    case read_resource(RawKey) of
        {ok, Vals} ->
            {{ok, Vals}, State};
        R ->
            {R, State}
    end.

%% @doc Update an existing resource.
%%
%% The modified resource is validated before this function is called.
%% DONT allow update because if dictionary is modified then the
%% content created with older dictionary will not be readable.
%% This is the primary reason for disabling upadtes to already
%% existing dictionary within the system. DO NOT change this.
-spec update(egraph_callback:id(), egraph_k(), state()) -> {boolean(), state()}.
update(_Key, _V, State) ->
    {false, State}.

%% @doc Update an existing resource with some expiry seconds.
-spec update(egraph_callback:id(), egraph_k(), integer(), state()) ->
    {boolean(), state()}.
update(Key, V, _QsProplist, State) ->
    update(Key, V, State).

%% @doc Delete an existing resource.
-spec delete(egraph_callback:id(), state()) -> {boolean(), state()}.
delete(_Key, State) ->
    {false, State}.

%%%===================================================================
%%% Internal
%%%===================================================================

create_info(Info, State) ->
    #{ <<"id">> := Key,
       <<"dictionary">> := Dictionary } = Info,
    true = is_binary(Dictionary),
    RawKey = egraph_util:convert_to_integer(Key),
    TimeoutMsec = ?DEFAULT_MYSQL_TIMEOUT_MSEC,
    TableName = ?EGRAPH_TABLE_COMPRESSION_DICT,
    case read_resource(RawKey) of
        {error, not_found} ->
            case sql_insert_record(TableName, RawKey, Dictionary, TimeoutMsec) of
                true ->
                    {{true, egraph_util:convert_to_binary(Key)}, State};
                false ->
                    {false, State}
            end;
        {ok, _} ->
            {false, State}
    end.

-spec read_resource(integer()) -> {ok, [map()]} | {error, term()}.
read_resource(RawKey) ->
    TableName = ?EGRAPH_TABLE_COMPRESSION_DICT,
    Q = iolist_to_binary([<<"SELECT * FROM ">>,
                          TableName,
                          <<" WHERE `id`=?">>]),
    Params = [RawKey],
    read_generic_resource(Q, Params).

-spec read_max_resource() -> {ok, map()} | {error, term()}.
read_max_resource() ->
    TableName = ?EGRAPH_TABLE_COMPRESSION_DICT,
    Q = iolist_to_binary([<<"SELECT `id`,dictionary FROM ">>,
                          TableName,
                          <<" ORDER BY `id` DESC LIMIT 1">>]),
    Params = [],
    case read_generic_resource(Q, Params) of
        {ok, [R]} ->
            {ok, R};
        E ->
            E
    end.

-spec read_all_resource(ShardKey :: integer(),
                        Limit :: integer(),
                        Offset :: integer()) ->
    {ok, [map()], NewOffset :: integer()} | {error, term()}.
read_all_resource(_ShardKey, Limit, Offset) ->
    TableName = ?EGRAPH_TABLE_COMPRESSION_DICT,
    Q = iolist_to_binary([<<"SELECT * FROM ">>,
                          TableName,
                          <<" ORDER BY `id` ASC LIMIT ? OFFSET ?">>]),
    Params = [Limit, Offset],
    case read_generic_resource(Q, Params) of
        {ok, R} ->
            {ok, R, Offset + length(R)};
        E ->
            E
    end.

read_generic_resource(Query, Params) ->
    ConvertToMap = true,
    TimeoutMsec = ?DEFAULT_MYSQL_TIMEOUT_MSEC,
    case egraph_sql_util:mysql_query(
           [?EGRAPH_RO_MYSQL_POOL_NAME],
           Query, Params, TimeoutMsec, ConvertToMap) of
        {ok, Maps} ->
            {ok, Maps};
        Error ->
            Error
    end.

sql_insert_record(TableName, RawKey, Dictionary, TimeoutMsec) ->
    CreatedDateTime = qdate:to_date(erlang:system_time(second)),
    Q = iolist_to_binary([<<"INSERT INTO ">>,
                          TableName,
                          <<" VALUES(?, ?, ?)">>]),
    Params = [RawKey, CreatedDateTime, Dictionary],
    %% TODO: find out the cluster nodes which must persist this data
    %%       and save it there.
    case egraph_sql_util:mysql_write_query(
           ?EGRAPH_RW_MYSQL_POOL_NAME,
           Q, Params, TimeoutMsec) of
        ok -> true;
        _ -> false
    end.

