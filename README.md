# Erlang Process-Oriented Ring/Grid Graph and Message Passing

This Erlang code provides functionality to create a ring or a grid graph with desired dimensions, where each node is a process, and enables the sending of messages from a main node to all other nodes in the graph. each of the functions (for a ring or a grid) is implemented in two orientations: serial and parallel, so the user can measure running times and understand the trade-off between seriality and parallelism.

Implementation

The code is implemented using process-oriented programming in Erlang, with each node represented as a process. The ring graph is created by linking nodes in a circular manner, and the grid graph is created by linking nodes in a row-column arrangement.

Functions

ring_serial(N, M) -> {TotalTimeInt, Sent, Received}:
Creates an N nodes ring and forwards M copies of a message from process1 to the nodes towards the ring (serial implementation).
The returned value is a tuple with the running time of the function, and the number of senta and received messages (from the main node).

ring_parallel(N, M) -> {TotalTimeInt, Sent, Received}:
Creates an N nodes ring where each node is a process and implement the previous function in a parallel orientetion.

mesh_serial(N, M, C) -> {TotalTimeInt, Sent, Received}:
Creates an NxN matrix of nodes with a root node in the C entry. The main node sends M copies of a message to its neighbors and each neighbor spread it next.
After all of the nodes sent ack's to the main node, the timer freeze and the tuple is returned. (serial implementation).

mesh_parallel(N, M, C) -> {TotalTimeInt, Sent, Received}:
a parallel implementation of the previous function, such that each node is a process.

Motivation:
It can be concluded from testing with various N, M integers that there is a trade-off between seriality and parallelism.
In big graphs with high connectivity (mesh for example), parallel implementations.
In small graphs or graphs that are serial oriented (ring for example), the serial implementations are much faster, because parallelism's message passing takes too long in comparing to the scale of the problem.

Usage
To use this code, download the .erl file and compile it in your Erlang environment. You can then call the functions from a linux shell.
