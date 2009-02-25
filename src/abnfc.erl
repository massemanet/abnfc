%%%-------------------------------------------------------------------
%%% @copyright 2009 Anders Nygren
%%% @version  {@vsn} 
%%% @author Anders Nygren <anders.nygren@gmail.com>
%%% @doc 
%%% @end 
%%%-------------------------------------------------------------------
-module(abnfc).

%% API
-export([file/1, file/2,
	 parse/1, parse/2]).

-export([erlangcode/0]).

-compile(export_all).
%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% @spec (File::string()) -> {ok, AST, Rest::binary()} | Error
%% @doc Compile an ABNF file.
%% @end
%%--------------------------------------------------------------------
file(File) ->
    file(File,[]).

%%--------------------------------------------------------------------
%% @spec (File::string(), Opts) -> {ok, AST, Rest::binary()} | Error
%% Opts = [Option]
%% Option = OutFile
%% OutFile = string()
%% @doc Compile an ABNF file.
%% @end
%%--------------------------------------------------------------------
file(File, Opts) when is_list(Opts) ->
    case read_file(File) of
	{ok, Name, Text} ->
	    POpts = [],
	    GenOpts = gen_opts(Name, Opts),
	    COpts = compiler_opts(Opts),
	    case parse(Text, POpts) of
		{ok, AST, _Rest} ->
		    AST1 = abnfc_ast:ast_to_int_form(AST),
		    {ok, Code} = abnfc_gen:generate(AST1, GenOpts),
		    {ok, GenFile} = write_file(Code, GenOpts),
		    compile_file(GenFile, COpts);
		Error ->
		    Error
	    end;
	Error ->
	    Error
    end.

%%--------------------------------------------------------------------
%% @spec (Text) -> {ok, AST, Rest::binary()} | fail
%% Text = list() | binary()
%% @doc Parse a list or binary.
%% @end
%%--------------------------------------------------------------------
parse(Bin) ->
    parse(Bin, []).

%%--------------------------------------------------------------------
%% @spec (Text, Opts) -> {ok, AST, Rest::list()} | fail
%% Text = list() | binary()
%% @doc Parse a list or binary.
%% @end
%%--------------------------------------------------------------------
parse(Bin, Opts) when is_binary(Bin) ->
    parse(binary_to_list(Bin), Opts);

parse(String, _Opts) when is_list(String) ->
    case catch abnfc_rfc4234:rulelist_dec(String) of
	{ok, _Rulelist, []} =Result ->
	    Result;
	_Error ->
	    io:format("abnfc: failed~n",[])
    end.

%%--------------------------------------------------------------------
%% @spec () -> list()
%% @doc Scan erlang code.
%% @end
%%--------------------------------------------------------------------
erlangcode() ->
    fun (T) ->
	    scan(T)
    end.

scan(Input) ->
    case erl_scan:tokens([], Input, 1) of
	{done, {ok, Toks, _EndLine}, Extra} ->
	    Code = toks_to_list(Toks),
	    {ok, Code, Extra};
	{more, _Cont} ->
	    throw(end_of_input)
    end.

%%--------------------------------------------------------------------
%% @private 
%% @spec (Tokens) -> list()
%% @doc Convert tokens returned by erl_scan to a string again.
%% @end
%%--------------------------------------------------------------------
toks_to_list(Tokens) ->
    lists:foldl(fun({atom,L,Name},{Line, Acc}) ->
			{L,["'",Name,"'",sep(L,Line)|Acc]};
		   ({string,L,Name},{Line, Acc}) ->
			{L,["\"",Name,"\"",sep(L,Line)|Acc]};
		   ({_Type,L,Name},{Line, Acc}) ->
			{L,[Name,sep(L,Line)|Acc]};
		   ({dot,_L},{_Line,Acc}) ->
			lists:concat(lists:reverse(Acc));
		   ({Reserved, L},{Line,Acc}) ->
			{L,[Reserved,sep(L,Line)|Acc]}
		end, {1,[]}, Tokens).

sep(L,L) ->
    " ";
sep(_,_) ->
    "\n".

%%====================================================================
%% Internal functions
%%====================================================================
read_file(File) ->
    case string:tokens(filename:basename(File), ".") of
	[Name,"set","abnf"] ->
	    {ok, Files} = file:consult(File),
	    {ok, Name, lists:flatten([read_file1(F) || F <- Files])};
	[Name, "abnf"] ->
	    {ok, Name, read_file1(File)}
    end.

read_file1(File) ->
    {ok, Bin} = file:read_file(File),
    binary_to_list(Bin).
    
gen_opts(Name, Opts) ->
    Mod = proplists:get_value(mod, Opts, Name),
    [{mod,Mod}].

compiler_opts(Opts) ->
    OutDir = proplists:get_value(o, Opts, "./"),
    IncludeDirs = [{i,Dir}||Dir <- proplists:get_all_values(i, Opts)],
    [{outdir,OutDir}|IncludeDirs].
    
write_file(Code, Opts) ->
    Name = filename:join(proplists:get_value(o, Opts, "."),
			 proplists:get_value(mod, Opts))++".erl",
    io:format("abnfc: writing to ~p~n",[Name]),
    file:write_file(Name, Code),
    erl_tidy:file(Name,[{backups,false}]),
    {ok,Name}.

compile_file(File, Opts) ->
    io:format("abnfc: compiling ~p opts = ~p~n",[File, Opts]),
    compile:file(File, Opts).
