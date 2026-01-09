{
  Barev Protocol - Avatar Management
  Handles avatar loading, caching, and vCard generation
}

unit BarevAvatar;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Base64, BarevTypes;

type
  { Avatar manager }
  TBarevAvatarManager = class
  private
    FMyAvatarPath: string;
    FMyAvatarHash: string;
    FMyAvatarData: string;
    FMyAvatarMimeType: string;
    FAvatarCacheDir: string;

    function DetectMimeType(const FileName: string): string;
  public
    constructor Create(const ACacheDir: string = '');
    destructor Destroy; override;

    { Load user's avatar }
    function LoadMyAvatar(const FilePath: string): Boolean;
    procedure ClearMyAvatar;

    { Save buddy's avatar to cache }
    function SaveBuddyAvatar(const Nick, IPv6, AvatarData, MimeType: string): string;

    { vCard generation }
    function GenerateMyVCard: string;

    { Avatar update for presence }
    function GenerateAvatarUpdate: string;

    { Parse vCard from XML }
    function ParseVCardAvatar(const VCardXML: string; out AvatarData, MimeType, Hash: string): Boolean;

    property MyAvatarPath: string read FMyAvatarPath;
    property MyAvatarHash: string read FMyAvatarHash;
    property MyAvatarData: string read FMyAvatarData;
    property MyAvatarMimeType: string read FMyAvatarMimeType;
    property AvatarCacheDir: string read FAvatarCacheDir write FAvatarCacheDir;
  end;

implementation

uses
  BarevXML;

{ TBarevAvatarManager }

constructor TBarevAvatarManager.Create(const ACacheDir: string);
begin
  inherited Create;

  if ACacheDir <> '' then
    FAvatarCacheDir := ACacheDir
  else
    FAvatarCacheDir := GetUserDir + '.barev' + PathDelim + 'avatars';

  // Create cache directory if it doesn't exist
  if not DirectoryExists(FAvatarCacheDir) then
    ForceDirectories(FAvatarCacheDir);
end;

destructor TBarevAvatarManager.Destroy;
begin
  inherited;
end;

function TBarevAvatarManager.DetectMimeType(const FileName: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));

  case Ext of
    '.png': Result := 'image/png';
    '.jpg', '.jpeg': Result := 'image/jpeg';
    '.gif': Result := 'image/gif';
    '.bmp': Result := 'image/bmp';
    '.webp': Result := 'image/webp';
  else
    Result := 'application/octet-stream';
  end;
end;

function TBarevAvatarManager.LoadMyAvatar(const FilePath: string): Boolean;
var
  FileStream: TFileStream;
  MemStream: TMemoryStream;
  Base64Stream: TStringStream;
  Encoder: TBase64EncodingStream;
begin
  Result := False;

  if not FileExists(FilePath) then
    Exit;

  try
    // Load file into memory
    FileStream := TFileStream.Create(FilePath, fmOpenRead or fmShareDenyWrite);
    try
      MemStream := TMemoryStream.Create;
      try
        MemStream.CopyFrom(FileStream, FileStream.Size);
        MemStream.Position := 0;

        // Encode to Base64
        Base64Stream := TStringStream.Create('');
        try
          Encoder := TBase64EncodingStream.Create(Base64Stream);
          try
            Encoder.CopyFrom(MemStream, MemStream.Size);
          finally
            Encoder.Free;
          end;

          FMyAvatarData := Base64Stream.DataString;
        finally
          Base64Stream.Free;
        end;
      finally
        MemStream.Free;
      end;
    finally
      FileStream.Free;
    end;

    // Detect MIME type
    FMyAvatarMimeType := DetectMimeType(FilePath);
    FMyAvatarPath := FilePath;

    // Compute hash
    FMyAvatarHash := ComputeSHA1Hash(FMyAvatarData);

    Result := True;
  except
    on E: Exception do
    begin
      FMyAvatarData := '';
      FMyAvatarHash := '';
      FMyAvatarMimeType := '';
      FMyAvatarPath := '';
    end;
  end;
end;

procedure TBarevAvatarManager.ClearMyAvatar;
begin
  FMyAvatarData := '';
  FMyAvatarHash := '';
  FMyAvatarMimeType := '';
  FMyAvatarPath := '';
end;

function TBarevAvatarManager.SaveBuddyAvatar(const Nick, IPv6, AvatarData, MimeType: string): string;
var
  FileName, Ext: string;
  FileStream: TFileStream;
  Decoder: TBase64DecodingStream;
  Base64Stream: TStringStream;
begin
  Result := '';

  if AvatarData = '' then
    Exit;

  // Determine file extension from MIME type
  if Pos('png', LowerCase(MimeType)) > 0 then
    Ext := '.png'
  else if Pos('jpeg', LowerCase(MimeType)) > 0 then
    Ext := '.jpg'
  else if Pos('gif', LowerCase(MimeType)) > 0 then
    Ext := '.gif'
  else
    Ext := '.dat';

  // Create filename: nick-ipv6-hash.ext
  FileName := FAvatarCacheDir + PathDelim + Nick + '-' +
              StringReplace(IPv6, ':', '_', [rfReplaceAll]) + Ext;

  try
    // Decode Base64 and save to file
    Base64Stream := TStringStream.Create(AvatarData);
    try
      Decoder := TBase64DecodingStream.Create(Base64Stream);
      try
        FileStream := TFileStream.Create(FileName, fmCreate);
        try
          FileStream.CopyFrom(Decoder, Decoder.Size);
        finally
          FileStream.Free;
        end;
      finally
        Decoder.Free;
      end;
    finally
      Base64Stream.Free;
    end;

    Result := FileName;
  except
    on E: Exception do
      Result := '';
  end;
end;

function TBarevAvatarManager.GenerateMyVCard: string;
var
  VCard: string;
begin
  VCard := '<vCard xmlns=''' + VCARD_NAMESPACE + '''>';

  if FMyAvatarData <> '' then
  begin
    VCard := VCard + '<PHOTO>';
    VCard := VCard + '<TYPE>' + XMLEscape(FMyAvatarMimeType) + '</TYPE>';
    VCard := VCard + '<BINVAL>' + FMyAvatarData + '</BINVAL>';
    VCard := VCard + '</PHOTO>';
  end;

  VCard := VCard + '</vCard>';
  Result := VCard;
end;

function TBarevAvatarManager.GenerateAvatarUpdate: string;
var
  Update: string;
begin
  Update := '<x xmlns=''' + VCARD_UPDATE_NAMESPACE + '''>';

  if FMyAvatarHash <> '' then
    Update := Update + '<photo>' + FMyAvatarHash + '</photo>'
  else
    Update := Update + '<photo/>';

  Update := Update + '</x>';
  Result := Update;
end;

function TBarevAvatarManager.ParseVCardAvatar(const VCardXML: string;
  out AvatarData, MimeType, Hash: string): Boolean;
var
  PhotoStart, PhotoEnd: Integer;
  TypeStart, TypeEnd: Integer;
  BinvalStart, BinvalEnd: Integer;
  PhotoXML: string;
begin
  Result := False;
  AvatarData := '';
  MimeType := '';
  Hash := '';

  // Find <PHOTO> element
  PhotoStart := Pos('<PHOTO>', VCardXML);
  if PhotoStart = 0 then
    Exit;

  PhotoEnd := Pos('</PHOTO>', VCardXML);
  if PhotoEnd = 0 then
    Exit;

  PhotoXML := Copy(VCardXML, PhotoStart + 7, PhotoEnd - PhotoStart - 7);

  // Extract TYPE
  TypeStart := Pos('<TYPE>', PhotoXML);
  TypeEnd := Pos('</TYPE>', PhotoXML);
  if (TypeStart > 0) and (TypeEnd > 0) then
    MimeType := Copy(PhotoXML, TypeStart + 6, TypeEnd - TypeStart - 6);

  // Extract BINVAL
  BinvalStart := Pos('<BINVAL>', PhotoXML);
  BinvalEnd := Pos('</BINVAL>', PhotoXML);
  if (BinvalStart > 0) and (BinvalEnd > 0) then
  begin
    AvatarData := Copy(PhotoXML, BinvalStart + 8, BinvalEnd - BinvalStart - 8);
    // Compute hash
    Hash := ComputeSHA1Hash(AvatarData);
    Result := True;
  end;
end;

end.