-module(messages_forwarding).
-author("Ron Zilber").
-export([ring_parallel/2, ring_serial/2, mesh_parallel/3, mesh_serial/3]).  

%% -------------------- ring_parallel(N,M)  ------------------------------------------------------------------------------------------------------------ %%
% Spread M copies of a message from the head process toward a ring of N processes

ring_parallel(N, M) ->
    StartTime = erlang:timestamp(),                                                       % Measure the starting time of the function
    put(startTime, StartTime), put(dupsAmount, M),
    Containing_List = [],                                                                 % Create a new list to store the Pids in
    List = ringProcessLoop(N - 1, M, Containing_List , self()),                           % (N - 1) Becuase the Nth place will be P1 (it's a cycle)           
    [H|T] = List,
    Ring = T ++ [H],
    H!{start, Ring, M},                     
    put(status, onRun), put(ring, Ring),
    ring_parallel().

ring_parallel() ->
    receive
        {done, EndTime} ->                                                                
            StartTime = get(startTime), M = get(dupsAmount),
            ElapsedTime = timer:now_diff(EndTime, StartTime)/1000,
            put(status, done),
            put(return_message, {ElapsedTime, M, M});

        _anyMessage->
            unknown_message_received  
    end,
    Status = get(status),
    if
        Status == done ->
            lists:map(fun(Pid)-> exit(Pid, finished) end, get(ring)),                     %  Terminate all involved processes
            get(return_message);                                                          %  Return {TimeInt, Received, Sent} tuple
        true->
            ring_parallel() 
        end.
% ------ ringProcessLoop --------------
ringProcessLoop(0, _M, List, _Pid_of_Calling_Function) ->                                 %  Afer N processes have been created, return the list of the N PIDs.
    List;
ringProcessLoop(Number, M, List, Pid_of_Calling_Function) ->
    Pid_Of_New_Node = spawn(fun() -> nodeProcess(Pid_of_Calling_Function, M) end),
    
    ringProcessLoop(Number - 1, M, List ++ [Pid_Of_New_Node], Pid_of_Calling_Function).   %  Add the new process to the PIDs list

% ------ nodeProcess ---------------
nodeProcess(Pid, M) ->                                                                    %  
    put(pid_of_caller , Pid), put(dups_Amount, M), put(status, onRun),
    nodeProcess().

nodeProcess()->
    receive
        {start, Ring, M}->                                                                %  Used to wake up process P1 and make him send M messages in the ring
            generateLoop(Ring, M, M);

        {[H | T], MessageNumber, _From} ->                                                %  Each node at the ring will forward the message to the next node                                  
            H ! {T, MessageNumber, self()};      
            
        {[], MessageNumber, _From} ->                                                     %  P1 will get an empty list and when the M-th message will arrive he will
            M = get(dups_Amount),                                                         %  send 'done' update to the calling function
            if
                MessageNumber == M ->
                    God = get(pid_of_caller),       % It's a joke
                    EndTime = erlang:timestamp(),
                    put(status, done),
                    God ! {done, EndTime};

                true -> ok
            end;       
        _anyMessage ->
            unknown_message_received
            
        end,
    Status = get(status),                                                                 %  Go back into the receive block only if the status is not 'done'
    if
        Status /= done ->
            nodeProcess();
        true-> ok
    end.
% ------ generateLoop -----------------------------                                       % Used to generate and forward M messages from P1 to P2
generateLoop([_H|_T], _Times_M , 0) -> 
    ok;
generateLoop([H|T], Times_M, Left_To_Send) ->
    H ! {T, Times_M - Left_To_Send + 1, self()},
    generateLoop([H|T], Times_M, Left_To_Send - 1). 
%% -------------------- ring_seriall(V,M)  ------------------------------------------------------------------------------------------------------------ %%
% Spread M copies of a message from the head process toward a ring of N nodes (in a serial implementation)
ring_serial(V, M) ->
    StartTime = erlang:timestamp(),                                                       % Measure the starting time of the function
    put(start_time ,StartTime),
    put(dups_amount, M),
    List = lists:seq(1, V), [H | T] = List,
    Ring = T ++ [H],
    Message = "hello in serial version~n",
    ring_serial(Ring, M, Message),

    MessageCount = M,
    self() ! {List, Message, MessageCount, MessageCount},
    Status = notDone,
    put(status, Status),
    ring_serial(). 
% ------ ring_serial -----------------------------
ring_serial(List, MessageCount, Message) ->
    self() ! {List, Message, MessageCount, MessageCount},
    ring_serial().

ring_serial() ->                                                                                         
    receive
        {[], _Message, _MessageCount, _Left} ->
            self()!{done};
            
        {[_H | T], Message, MessageCount, 1} ->
            self() ! {T, Message, MessageCount, MessageCount};

        {[H | T], Message, MessageCount, _To_Send} ->
            self() ! {[H | T], Message, MessageCount, _To_Send - 1};

        {done}->
            Status = done,
            EndTime = erlang:timestamp(),
            put(status,Status),
            put(end_time ,EndTime);           
        _ ->
            ok
    end,
    ProcessStatus = get(status),
    if
        ProcessStatus /= done ->
            ring_serial();
        true ->
            Start_Time = get(start_time), End_Time = get(end_time), 
            %io:format("Start: ~p End: ~p~n", [Start_Time, End_Time]),

            ElapsedTime = timer:now_diff(End_Time, Start_Time)/1000, M = get(dups_amount),
            {ElapsedTime, M, M}
    end.
%% -------------------- mesh_parallel(N,M, C)  ------------------------------------------------------------------------------------------------------------ %%
% Spread M copies of a message from a main process toward a mesh of NxN processes (avoid duplications/ messages storms)
mesh_parallel(N, M, C) ->
    StartTime = erlang:timestamp(),                                                      % Measure the starting time of the function
    Mesh = meshProcessLoop(N * N, N, [], C, self()),                                     % Returns a list of length N^2 that represents the NxN mesh
    lists:map(fun(Process) -> notify(Process, Mesh) end, Mesh),
    MainProcess = lists:nth(C, Mesh),
    MainProcess ! {mainProcess, M, StartTime},
    mesh_parallel().
     
mesh_parallel()->
    put(status, notDone),
    receive
        {IntTime, Sent, Received}->
            Message = {IntTime, Sent, Received},
            put(return_message, Message), put(status, done);
            
        _anyMessage->
            ok
    end,
    Status = get(status),
    if
        Status /= done->
            mesh_parallel();
        true-> get(return_message)
    end.
% ------ getNeighbors -----------------------------                      %  Generates a list of neighbor indexes of an input index in an NxN grid
getNeighbors(1, _Index) ->                                               %  If N = 1, an NxN grid is not possible...
    [];
getNeighbors(N, Index) ->
    Klist = lists:seq(-N,N),
    Left_Right_List = left_right_neighbors(Klist, N, Index, []),
    Up_Down_List = up_down_neighbors(N, Index),
    _NeighborsList = lists:sort(Left_Right_List ++ Up_Down_List).

% --------------------------------------------------
left_right_neighbors([], _N, _Index, OutputList) ->
    OutputList;
left_right_neighbors([H | T], N, Index, OutputList) ->
    if
        ((1 + H * N) < Index) and (Index < (H + 1) * N) ->
            List = OutputList ++ [Index - 1, Index + 1],
            left_right_neighbors([], N, Index, List);
        (Index == 1 + H * N) ->
            List = OutputList ++ [Index + 1],
            left_right_neighbors([], N, Index, List);
        (Index == H * N) ->
            List = OutputList ++ [Index - 1],
            left_right_neighbors([], N, Index, List);
        true ->
            left_right_neighbors(T, N, Index, [])
    end.
% --------------------------------------------------
up_down_neighbors(N, Index) ->                                           
    if
        (0 < Index - N) and (Index + N =< N * N) ->
            List = [Index - N, Index + N];
        (0 < Index - N) ->
            List = [Index - N];
        (Index + N =< N * N) ->
            List = [Index + N];
        true ->
            List = []
    end,
    List.
% ----------------------------------------------------
notify(Process, List) ->                                                 %  Send a message that contain a list, to a given pid
    Process ! {list, List}.
% ----------------------------------------------------
meshProcess(MailBox, N, C, Pid_of_Calling_Function) ->                   %  Initialize a new process with an empty mailbox (the argument MailBox is an empty list)                        
    put(type, member),                                                   %  Mark the process as a member (and not the leader)
    MailBox = [], put(n, N),
    put(mailbox, MailBox), put(c, C),                                    %  C is the number of the leader
    put(pid_of_caller, Pid_of_Calling_Function),
    meshProcess().
% ---------------------------------------------------                    %  The receive block for the processes in the mesh
meshProcess() ->
    receive
        {list, Mesh} -> 
            N = get(n),                          
            Index = string:str(Mesh, [self()]),                          %  Returns the index of the process in the list of the pids
            NeighborsIndexes = getNeighbors(N, Index),
            MyNeighbors = [lists:nth(Indx, Mesh) || Indx <- NeighborsIndexes],
            put(mesh, Mesh),
            put(neighbors_list, MyNeighbors),
            put(index, Index);
                       
        {mainProcess, DupsAmount, StartTime} ->           
            AcksList = [],                                                % Collects the acknowledgments from the mesh nodes
            put(acks_list, AcksList),put(dups_amount,DupsAmount), put(start_time, StartTime), put(type, leader), MyNeighbors = get(neighbors_list),
            spreadMessages(get(c), MyNeighbors, DupsAmount, DupsAmount);
        
        {SourcePid, MessageNumber} ->
            Message = {SourcePid, MessageNumber},
            Already_in_mailBox = lists:member(Message, get(mailbox)),    %  lists:member returns false in case the element is not 
                                                                         %  found and a value (that we will not use) in case it is found in the list      
            ProcessType = get(type),            
            if
                (ProcessType == leader) ->
                    AcksList = get(acks_list), C = get(c),
                      
                    InAcks = lists:member(Message, AcksList),            %  InAcks is a boolean: whether the akc has already accpeted or not
                    if
                        not(InAcks) and (SourcePid /= C) ->
                            NewList = lists:sort(lists:append(AcksList, [Message])),
                            put(acks_list, NewList), 
                            Length = (length(get(mesh)) - 1) * get(dups_amount),
                            if
                                (Length == (length(NewList))) ->
                                    ok,
                                put(type, done);
                                true-> ok
                            end;
                        true-> ok
                    end;

                Already_in_mailBox->                                     %  If the message is already in the mailbox, ignore from it
                    ok;
                                              
                (ProcessType /= leader) ->
                    MailBox = get(mailbox), C = get(c), MyNeighbors = get(neighbors_list),
                    if
                        SourcePid == C->               % The message is from the main process
                            lists:map(fun(Pid) -> Pid!{self(), MessageNumber} end, MyNeighbors);  

                        true->                         % The message is from another process
                            ok 
                        end,

                    put(mailbox,lists:append(MailBox,[Message])),
                    
                    lists:map(fun(Pid) -> Pid!{SourcePid, MessageNumber} end, MyNeighbors);
                                            
                true->
                    ok                       
            end;        
        _anyMessage ->    ok
    end,
    Status = get(type),

    if
        Status == done ->
            Acks_List = get(acks_list), M_Copies = get(dups_amount), Nsquared = length(get(mesh)), Start_Time = get(start_time), NeighborsList = get(neighbors_list),
            if                   
                length(Acks_List) == (Nsquared- 1) * M_Copies ->
                    EndTime = erlang:timestamp(),
                    ElapsedTime = timer:now_diff(EndTime, Start_Time)/1000,
                    get(pid_of_caller)!{ElapsedTime, M_Copies *length(NeighborsList), (Nsquared - 1) * M_Copies};
                   ok;  
                true -> 
                    meshProcess()
            end;    
        true ->        
        meshProcess()
    end.
    
spreadMessages(_Message, [], _DupsAmount, _Left) ->                                 % Spread M messages to each element in a given list
    ok;
spreadMessages(Message, [_H | T], DupsAmount, 0) ->
    spreadMessages(Message, T, DupsAmount, DupsAmount);
spreadMessages(Message, [H | T], DupsAmount, _To_Send) ->
    H ! {Message, DupsAmount - _To_Send + 1},
    spreadMessages(Message, [H | T], DupsAmount, _To_Send - 1).

% ------ meshProcessLoop --------------
meshProcessLoop(0, _N, List, _C, _Pid) -> List;                                     %  Afer N processes have been created, return the list of the N PIDs.
meshProcessLoop(Number, N, List , C, Pid) ->
    PID = spawn(fun() -> meshProcess([] , N, C, Pid) end),   
    meshProcessLoop(Number - 1, N, List ++ [PID], C, Pid).                          %  Add the new process to the PIDs list

%% -------------------- mesh_serial(N, M, C)  ------------------------------------------------------------------------------------------------------------ %%
% Spread M copies of a message from a main process toward a mesh of NxN nodes (avoid duplications/ messages storms) - serial implemantation
mesh_serial(N,M,C)->
    StartTime = erlang:timestamp(),                                                 %  Measure the starting time of the function
    Nsquare = N*N,   
    Mesh = lists:seq(1, Nsquare),   
    NeighborsLists = lists:map(fun(Index) -> getNeighbors(N, Index) end, Mesh),     %  Create a neighbors list for each process in the mesh
     
    NeighborsOfMainProcess = lists:nth(C, NeighborsLists),                          %  Compute the neighbors list of the main process
    MailBoxes = [[] || _<- Mesh],                                                   %  Create N^2 empty mailboxes
    put(mesh, Mesh), 
    put(neighbors_lists, NeighborsLists), 
    put(c, C), put(mailboxes, MailBoxes),
    put(m, M), put(start_time, StartTime),  
    lists:map(fun(Dest_Neighbor) -> serialSpreadMessages({C,Dest_Neighbor}, M, M) end, NeighborsOfMainProcess),
    mesh_serial().
 
mesh_serial()-> 
    C = get(c), Nsquare = length(get(mesh)),
    receive   
        {{SourceIndex, MessageNumber}, Destination} ->   % Arguments meaning: (1) Who sent it (2) The nth copy (out of M copies) (3) The destination node                    
            MailBoxesList = get(mailboxes), 
            Dest_MailBox = lists:nth(Destination, MailBoxesList), 
            Already_in_mailBox = lists:member({SourceIndex, MessageNumber}, Dest_MailBox),

            if 
                (not(Already_in_mailBox) and not(SourceIndex == Destination )) -> % No need for 'self acking' so message with same source and destination are ignored
                   
                    Append_MailBox = lists:append(Dest_MailBox, [{SourceIndex, MessageNumber}]),                  
                    if                                   % This 'if' block is used to prevent from trying to access illegal index (smaller that 1 or bigger than N^2)
                        (Destination == 1) ->  
                            Append_MailBoxesList = [Append_MailBox] ++ lists:nthtail(1, MailBoxesList);
                           
                        (Destination == Nsquare) ->                          % It's the N^2 -th node the (last one)     
                            Append_MailBoxesList = lists:sublist(MailBoxesList, length(MailBoxesList) - 1) ++ [Append_MailBox];
                          
                        true ->                                              % Just some node at the middle (index respects:     1 < index < N^2 )
                            Append_MailBoxesList = lists:sublist(MailBoxesList, Destination - 1) ++ [Append_MailBox] ++ lists:nthtail(Destination, MailBoxesList)
                    end,

                    put(mailboxes, Append_MailBoxesList),
                    Receiver_Neighbors_List = lists:nth(Destination, get(neighbors_lists)),                   
                    if
                        (Destination /= C) and (SourceIndex == C)->          %  The receiving node is not the main node and the message is from the main node

                        %   Produce a message with your index and sent it to all of your neighbors and *also* forward the received message:
                            lists:map(fun(Dest_Neighbor) -> self()!{{SourceIndex,MessageNumber},Dest_Neighbor} end, Receiver_Neighbors_List),
                            lists:map(fun(Dest_Neighbor) -> self()!{{Destination,MessageNumber},Dest_Neighbor} end, Receiver_Neighbors_List);

                        ((Destination /= C) and (SourceIndex /= C))->        %  The receiving node is not the main node and the message is not from the main node
                        %   Only forward the receving message:    
                            lists:map(fun(Dest_Neighbor) -> self()!{{SourceIndex,MessageNumber},Dest_Neighbor} end, Receiver_Neighbors_List);

                        true->                                               %  The receiving node is the main node and shall pass no arrival messages
                            DupsAmount = get(m),
                            if
                                length(Append_MailBox) == ((Nsquare - 1) * DupsAmount) ->               
                                    put(status, done);                                   
                                true-> ok     
                            end
                    end;
                true -> 
                    ok
            end;                                                                          
        _anyMessage ->
            unknown_message_received
    end,
    StartTime = get(start_time),
    EndCondition = get(status),  
    if
        EndCondition == done ->
            EndTime = erlang:timestamp(), M = get(m), C = get(c), 
            ElapsedTime = timer:now_diff(EndTime, StartTime)/1000,
            
            {ElapsedTime, M*length(lists:nth(C, get(neighbors_lists))), M*(Nsquare-1)};
        true->
    mesh_serial()
    end.
 % --------------------------------------------------------------    
serialSpreadMessages(_Message, _M_, 0) -> ok;                                                %   Spreads M copies of a message to each element in a given list
serialSpreadMessages({SourceIndex,Dest_Neighbor}, M, _To_Send)->
    self()!{{SourceIndex,M - _To_Send + 1}, Dest_Neighbor},  
    serialSpreadMessages({SourceIndex,Dest_Neighbor}, M, _To_Send - 1).
%% ------------------ Thanks for reading --------------------------------------------------------------------------------------------------------------------------------- %%