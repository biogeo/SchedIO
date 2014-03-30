classdef SchedIO < handle
% SchedIO  A class for interacting with an Arduino running SchedIO.pde
% This class defines a simplified interface for interacting with an Arduino
% running the SchedIO.pde sketch for use as a simple digital I/O device.
% The major use of this sketch is to give commands to the Arduino to
% schedule changes in the I/O lines without requiring further input from
% the computer running Matlab. This allows a very short command to cause
% the Arduino to produce, for example, a 50 ms digital pulse, letting the
% computer "fire-and-forget."
% 
% This class is designed for use with Psychtoolbox, specifically its IOPort
% function.
    properties (SetAccess=private)
        port_name
        port_ptr
    end
    properties (Constant)
        cmdByteSetHigh   = 1;
        cmdByteSetLow    = 2;
        cmdBytePulseHigh = 3;
        cmdBytePulseLow  = 4;
        cmdByteDelayHigh = 5;
        cmdByteDelayLow  = 6;
    end
    
    methods
        function obj = SchedIO(port_name)
% SchedIO  Get a handle to a SchedIO object
% Usage:
%     h = SchedIO(port_name)
% Returns an interface to an Arduino running the SchedIO.pde sketch.
% port_name is a string naming the serial port that the device is attached
% to. E.g., on Windows, it could be 'COM1', or on Linux, '/dev/ttyUSB0'. If
% the connection is not already open, it will be initialized -- otherwise,
% an interface to the already-opened connection will be returned. When all
% handles to the SchedIO interface are deleted, the serial port will be
% closed.
            obj.port_name = port_name;
            obj.port_ptr = SchedIO.reference_counter(port_name, true);
        end
        
        function delete(obj)
            SchedIO.reference_counter(obj.port_name, false);
        end
        
        function when = SetPin(obj, pin, value)
            % Usage:
            %     when = obj.SetPin(pin, value)
            % Send a command to the digital output server to set a specific
            % pin either high or low immediately. "value" should be 1 or 0,
            % or true or false, to indicate high or low, respectively.
            % "when" is the time at which the command was sent.
            cmd_bytes = [2-value pin];
            [n, when] = IOPort('Write', obj.port_ptr, uint8(cmd_bytes));
        end
        
        function when = PulsePin(obj, pin, value, time_ms)
            % Usage:
            %     when = obj.PulsePin(pin, value, time_ms)
            % Send a command to the digital output server to set a specific
            % pin either high or low for some duration, then set the pin to
            % the opposite value.  "value" should be 1 or 0, or true or
            % false, to indicate a high or low pulse, respectively.
            % "time_ms" is the duration of the pulse, in milliseconds (max
            % 65535). "when" is the time at which the command was sent.
            cmd_bytes = [4-value pin floor(time_ms/255) mod(time_ms,255)];
            [n, when] = IOPort('Write', obj.port_ptr, uint8(cmd_bytes));
        end
        
        function when = DelaySetPin(obj, pin, value, time_ms)
            % Usage:
            %     when = obj.DelaySetPin(pin, value, time_ms)
            % Send a command to the digital output server to set a specific
            % pin high or low after a delay. "value" should be 1 or 0, or
            % true or false, to indicate a high or low pulse, respectively.
            % "time_ms" is the duration of the delay before setting the
            % pin, in milliseconds (max 65535). "when" is the time at which
            % the command was sent.
            cmd_bytes = [6-value pin floor(time_ms/255) mod(time_ms,255)];
            [n, when] = IOPort('Write', obj.port_ptr, uint8(cmd_bytes));
        end
        
        function when = SendBytes(obj, bytes)
            % Usage:
            %     when = h.SendBytes(bytes)
            % Send a stream of bytes to the digital output server. Only use
            % this if you know what you're doing: otherwise you could crash
            % the program on the Arduino (which would then only need to be
            % reset, but could be annoying to debug). The main reason to do
            % this would be to send multiple commands as part of the same
            % serial write operation, slightly improving performance. Best
            % used in conjunction with GetCommandBytes, as in the following
            % example:
            % >> bytes = h.GetCommandBytes('SetHigh', 3);
            % >> bytes = [bytes, h.GetCommandBytes('DelayLow', 4, 1000)];
            % >> bytes = [bytes, h.GetCommandBytes('PulseHigh', 5, 500)];
            % >> h.SendBytes(bytes)
            % This example would set pin 3 high immediately, set pin 4 high
            % in 1000 ms, and pulse pin 5 high for 500 ms, all starting at
            % the same time (with some slight delay associated with the
            % Arduino processing each command).
            [n, when] = IOPort('Write', obj.port_ptr, bytes);
        end
    end
    
    methods (Static)
        function bytes = GetCommandBytes(command, pin, time_ms)
            [iscmd, cmd_num] = ismember(lower(command), ...
                {'sethigh', 'setlow', 'pulsehigh', 'pulselow', ...
                'delayhigh', 'delaylow'});
            if ~iscmd
                error('SchedIO:badCommand', 'Invalid command string.');
            end
            if ismember(cmd_num, [1 2])
                bytes = uint8([cmd_num, pin]);
            else
                bytes = uint8([cmd_num, pin, ...
                    floor(time_ms/255), mod(time_ms, 255)]);
            end
        end
    end
    
    methods (Static, Access=private)
        function port_ptr = reference_counter(port, is_increment)
            persistent ports
            persistent counts
            persistent port_ptrs
            if isempty(ports)
                ports = {};
            end
            [is_present, index] = ismember(port, ports);
            if ~is_present
                ports{end+1} = port;
                counts(end+1) = 0;
                port_ptrs(end+1) = 0;
                index = numel(counts);
            end
            if is_increment
                % We are opening a new reference to the port
                if counts(index) == 0
                    % We are opening a new port
                    port_ptrs(index) = IOPort('OpenSerialPort', ...
                        port, 'BaudRate=115200 Lenient');
                end
                counts(index) = counts(index) + 1;
                port_ptr = port_ptrs(index);
            else
                % We are closing a reference to the port
                counts(index) = counts(index) - 1;
                if counts(index) == 0
                    % No more references remain: close the port.
                    IOPort('Close',port_ptrs(index));
                end
                port_ptr = 0;
            end
        end
    end
end