classdef ExampleIO < SchedIO
% This is an example of how to subclass SchedIO for more specific uses.
% SchedIO provides a generic interface, e.g., PulsePin, which gives full
% control over the Arduino running SchedIO.pde, but this generic interface
% does not give semantic cues for the specific functions the Arduino is
% performing. Subclassing SchedIO for your specific purposes will make the
% code that calls the Arduino interface cleaner, easier to read, and less
% prone to bugs.
% 
% To use this file as a template for your own code, make a copy with a new
% name, like "MyProjectIO.m", and change all instances of "ExampleIO" in
% the file to the new name. For example, line 1 should read:
%     classdef MyProjectIO < SchedIO
% Then, see the comments in-line, below, for other things to change.

    properties (Constant)
        % syncPulseWidth specifies the default width of synchronizing
        % event pulses, in milliseconds. Choose a value that is appropriate
        % for your application:
        syncPulseWidth = 10;
    end
    
    methods
        % This function is the class constructor. It should be renamed to
        % reflect the new file name you've chosen. Any additional commands
        % that should be executed on setting up the connection can be given
        % here. For example, if one or more pins should be initialized to
        % high logic rather than low, add commands like this:
        %     obj.SetPin(pin, 1);
        function obj = ExampleIO(port_name)
            obj = obj@SchedIO(port_name);
        end
        
        % This function labels a specific pin (in this case, pin 2) as
        % serving a specific purpose, (in this case, "OpenSolenoid",
        % meaning the output pin controls a solenoid). The function accepts
        % the duration of the controlling pulse as a parameter, and the
        % time at which the command was sent to the Arduino is returned.
        % Rename this function and/or change the pin number to meet your
        % needs.
        function when = OpenSolenoid(obj, duration)
            when = obj.PulsePin(2, 1, duration);
        end
        
        % The following two functions label specific pins (3 and 4) as
        % serving to provide synchronizing event pulses. The width of these
        % pulses is given by the syncPulseWidth constant, defined above.
        % Change these functions' names to something that provides better
        % semantics for your purposes, like "TrialStart", and set the pin
        % numbers appropriately.
        function when = Event1(obj)
            when = obj.PulsePin(3, 1, obj.syncPulseWidth);
        end
        function when = Event2(obj)
            when = obj.PulsePin(4, 1, obj.syncPulseWidth);
        end
    end
end