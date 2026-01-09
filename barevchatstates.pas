{
  Barev Protocol - Chat State Notifications (Typing indicators)
  Implements XEP-0085: Chat State Notifications
}

unit BarevChatStates;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BarevTypes;

type
  { Chat state }
  TChatState = (
    csActive,      // User is actively participating in chat
    csInactive,    // User has not interacted with chat for a while
    csGone,        // User has left the conversation
    csComposing,   // User is typing
    csPaused       // User stopped typing
  );

  { Chat state manager }
  TBarevChatStates = class
  public
    class function ChatStateToString(State: TChatState): string;
    class function StringToChatState(const StateStr: string): TChatState;

    { Generate chat state notification XML }
    class function GenerateChatState(State: TChatState; const ToJID: string): string;

    { Parse chat state from message XML }
    class function ParseChatState(const MessageXML: string): TChatState;
  end;

implementation

uses
  BarevXML;

{ TBarevChatStates }

class function TBarevChatStates.ChatStateToString(State: TChatState): string;
begin
  case State of
    csActive: Result := 'active';
    csInactive: Result := 'inactive';
    csGone: Result := 'gone';
    csComposing: Result := 'composing';
    csPaused: Result := 'paused';
  else
    Result := 'active';
  end;
end;

class function TBarevChatStates.StringToChatState(const StateStr: string): TChatState;
begin
  if StateStr = 'composing' then
    Result := csComposing
  else if StateStr = 'paused' then
    Result := csPaused
  else if StateStr = 'inactive' then
    Result := csInactive
  else if StateStr = 'gone' then
    Result := csGone
  else
    Result := csActive;
end;

class function TBarevChatStates.GenerateChatState(State: TChatState; const ToJID: string): string;
var
  StateStr: string;
  MessageID: string;
begin
  StateStr := ChatStateToString(State);
  MessageID := GenerateID('chat');

  Result := '<message type=''chat'' to=''' + XMLEscape(ToJID) + ''' id=''' + MessageID + '''>' +
            '<' + StateStr + ' xmlns=''' + CHATSTATES_NAMESPACE + '''/>' +
            '</message>';
end;

class function TBarevChatStates.ParseChatState(const MessageXML: string): TChatState;
var
  States: array[0..4] of string = ('composing', 'paused', 'active', 'inactive', 'gone');
  i: Integer;
  SearchTag: string;
begin
  Result := csActive; // Default

  // Look for chat state elements (try both single and double quotes)
  for i := 0 to High(States) do
  begin
    SearchTag := '<' + States[i] + ' xmlns=''' + CHATSTATES_NAMESPACE + '''';
    if Pos(SearchTag, MessageXML) > 0 then
    begin
      Result := StringToChatState(States[i]);
      Exit;
    end;
    
    // Also try double quotes for compatibility
    SearchTag := '<' + States[i] + ' xmlns="' + CHATSTATES_NAMESPACE + '"';
    if Pos(SearchTag, MessageXML) > 0 then
    begin
      Result := StringToChatState(States[i]);
      Exit;
    end;
  end;
end;

end.