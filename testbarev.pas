{
  Simple Barev Test Program
  Demonstrates basic usage of the Barev library
}

program TestBarev;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, Barev, BarevTypes;

type
  TEventHandler = class
    procedure OnLog(const LogLevel, Message: string);
    procedure OnBuddyStatus(Buddy: TBarevBuddy; OldStatus, NewStatus: TBuddyStatus);
    procedure OnMessageReceived(Buddy: TBarevBuddy; const MessageText: string);
    procedure OnConnectionState(Buddy: TBarevBuddy; State: TConnectionState);
  end;

type
  TNetThread = class(TThread)
  private
    FClient: TBarevClient;
  protected
    procedure Execute; override;
  public
    constructor Create(AClient: TBarevClient);
  end;

var
  Client: TBarevClient;
  Quit: Boolean;
  Handler: TEventHandler;
  Command: string;
  Parts: TStringList;
  IPv6Addr: string;
  Buddy: TBarevBuddy;
  i: Integer;
  tmpNick, tmpAddr: string;
  NetThread: TNetThread;


constructor TNetThread.Create(AClient: TBarevClient);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FClient := AClient;
end;

procedure TNetThread.Execute;
begin
  while not Terminated do
  begin
    FClient.Process;
    Sleep(20); // 20ms is fine for interactive
  end;
end;

procedure TEventHandler.OnLog(const LogLevel, Message: string);
begin
  WriteLn('[', LogLevel, '] ', Message);
end;

procedure TEventHandler.OnBuddyStatus(Buddy: TBarevBuddy; OldStatus, NewStatus: TBuddyStatus);
begin
  WriteLn('*** ', Buddy.Nick, ' is now ', StatusToString(NewStatus));
end;

procedure TEventHandler.OnMessageReceived(Buddy: TBarevBuddy; const MessageText: string);
begin
  WriteLn;
  WriteLn('*** Message from ', Buddy.Nick, ': ', MessageText);
  Write('> ');  // Re-show prompt
  Flush(Output);
end;

procedure TEventHandler.OnConnectionState(Buddy: TBarevBuddy; State: TConnectionState);
const
  StateNames: array[TConnectionState] of string = (
    'Disconnected', 'Connecting', 'StreamInit', 'Authenticated', 'Online'
  );
begin
  WriteLn('*** Connection to ', Buddy.Nick, ': ', StateNames[State]);
end;

procedure ShowHelp;
begin
  WriteLn('Commands:');
  WriteLn('  help                  - Show this help');
  WriteLn('  add <nick@ipv6>       - Add a buddy');
  WriteLn('  list                  - List all buddies');
  WriteLn('  connect <nick@ipv6>   - Connect to a buddy');
  WriteLn('  msg <nick@ipv6> <text> - Send a message');
  WriteLn('  status <status> [msg] - Set your status (available/away/dnd)');
  WriteLn('  load <file>           - Load contacts from file');
  WriteLn('  save <file>           - Save contacts to file');
  WriteLn('  quit                  - Exit the program');
  WriteLn;
end;

begin
  WriteLn('Barev Test Program');
  WriteLn('==================');
  WriteLn;

  // Get local configuration
  Write('Enter your nick: ');
  ReadLn(Command);

  if Command = '' then
  begin
    WriteLn('Error: Nick is required');
    Halt(1);
  end;

  Write('Enter your Yggdrasil IPv6 address: ');
  ReadLn(IPv6Addr);

  if (IPv6Addr = '') or not IsYggdrasilAddress(IPv6Addr) then
  begin
    WriteLn('Error: Valid Yggdrasil IPv6 address is required');
    WriteLn('(Should start with 200:, 201:, 202:, 203:, 300:, 301:, 302:, 303:, 3ff:, etc.)');
    Halt(1);
  end;

  WriteLn;
  WriteLn('Starting Barev client...');

  Parts := TStringList.Create;
  // Create client
  Client := TBarevClient.Create(Command, IPv6Addr);

  if not Client.Start then
  begin
    WriteLn('Failed to start client');
    Client.Free;
    Halt(1);
  end;

  WriteLn('Client started successfully as ', Client.MyJID);
  WriteLn('Listening on port ', Client.Port);
  WriteLn;
  WriteLn('Type "help" for commands');
  WriteLn;

  Handler := TEventHandler.Create;

  Client.OnLog             := @Handler.OnLog;
  Client.OnBuddyStatus     := @Handler.OnBuddyStatus;
  Client.OnMessageReceived := @Handler.OnMessageReceived;
  Client.OnConnectionState := @Handler.OnConnectionState;


  Parts := TStringList.Create;
  Quit := False;

  NetThread := TNetThread.Create(Client);

  try
    while not Quit do
    begin
      // Process network events
      Client.Process;

      // Check for user input (non-blocking would be better, but this is simple)
      Write('> ');
      ReadLn(Command);
      Command := Trim(Command);

      if Command = '' then Continue;

      // Split command into parts
      Parts.Clear;
      Parts.Delimiter := ' ';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := Command;

      if Parts.Count = 0 then Continue;

      // Process command
      case LowerCase(Parts[0]) of
        'help':
          ShowHelp;

        'quit', 'exit':
          Quit := True;

      'add':
        begin
          if Parts.Count < 2 then
            WriteLn('Usage: add <nick@ipv6>')
          else
            if ParseJID(Parts[1], tmpNick, tmpAddr) then
            begin
              Buddy := Client.AddBuddy(tmpNick, tmpAddr);
              if Assigned(Buddy) then
                WriteLn('Added buddy: ', Buddy.JID)
              else
                WriteLn('Failed to add buddy');
            end
            else
              WriteLn('Invalid JID format. Use: nick@ipv6');
        end;


        'list':
          begin
            WriteLn('Buddies (', Client.GetBuddyCount, '):');
            for i := 0 to Client.GetBuddyCount - 1 do
            begin
              Buddy := Client.GetBuddyByIndex(i);
              WriteLn('  ', Buddy.Nick, '@', Buddy.IPv6Address, ':', Buddy.Port,
                     ' - ', StatusToString(Buddy.Status));
            end;
          end;

        'connect':
          begin
            if Parts.Count < 2 then
              WriteLn('Usage: connect <nick@ipv6>')
            else
            begin
              if Client.ConnectToBuddy(Parts[1]) then
                WriteLn('Connecting to ', Parts[1], '...')
              else
                WriteLn('Failed to connect to ', Parts[1]);
            end;
          end;

        'msg':
          begin
            if Parts.Count < 3 then
              WriteLn('Usage: msg <nick@ipv6> <message>')
            else
            begin
              // Join all parts after the JID as the message
              Command := '';
              for i := 2 to Parts.Count - 1 do
              begin
                if i > 2 then Command := Command + ' ';
                Command := Command + Parts[i];
              end;

              if Client.SendMessage(Parts[1], Command) then
                WriteLn('Message sent to ', Parts[1])
              else
                WriteLn('Failed to send message to ', Parts[1]);
            end;
          end;

        'status':
          begin
            if Parts.Count < 2 then
              WriteLn('Usage: status <available|away|dnd> [message]')
            else
            begin
              Command := '';
              if Parts.Count > 2 then
              begin
                for i := 2 to Parts.Count - 1 do
                begin
                  if i > 2 then Command := Command + ' ';
                  Command := Command + Parts[i];
                end;
              end;

              if Client.SendPresence(StringToStatus(Parts[1]), Command) then
                WriteLn('Status updated')
              else
                WriteLn('Failed to update status');
            end;
          end;

        'load':
          begin
            if Parts.Count < 2 then
              WriteLn('Usage: load <filename>')
            else
            begin
              if Client.LoadContactsFromFile(Parts[1]) then
                WriteLn('Loaded contacts from ', Parts[1])
              else
                WriteLn('Failed to load contacts from ', Parts[1]);
            end;
          end;

        'save':
          begin
            if Parts.Count < 2 then
              WriteLn('Usage: save <filename>')
            else
            begin
              if Client.SaveContactsToFile(Parts[1]) then
                WriteLn('Saved contacts to ', Parts[1])
              else
                WriteLn('Failed to save contacts to ', Parts[1]);
            end;
          end;

      else
        WriteLn('Unknown command: ', Parts[0]);
        WriteLn('Type "help" for commands');
      end;
    end;
  finally

      if Assigned(NetThread) then
      begin
        NetThread.Terminate;
        NetThread.WaitFor;
        NetThread.Free;
      end;

      if Assigned(Client) then
      begin
        Client.Stop;   // optional if Free calls destructor that closes sockets anyway
        Client.Free;
      end;

      FreeAndNil(Parts);
      FreeAndNil(Handler);

  end;

  WriteLn('Goodbye!');
end.
