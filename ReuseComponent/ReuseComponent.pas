{ ReuseComponent: native Altium script. }

Function RC_Support_FL_IsFootprint(Model : ISch_Implementation) : Boolean;
Begin
    Result := UpperCase(Trim(Model.ModelType)) = 'PCBLIB';
End;

Function RC_Support_FL_FindOwningProject(Doc : ISch_Document; Var Count : Integer) : IProject;
Var
    Workspace : IWorkspace;
    Project   : IProject;
    Owner     : IProject;
    I         : Integer;
Begin
    Result := Nil; Count := 0;
    Workspace := GetWorkspace;
    If Workspace = Nil Then Exit;
    { Running a script can focus its PrjScr. Require actual SchDoc membership. }
    Project := Workspace.DM_FocusedProject;
    If Project <> Nil Then
        If UpperCase(ExtractFileExt(Project.DM_ProjectFullPath)) = '.PRJPCB' Then
            If Project.DM_GetDocumentFromPath(Doc.DocumentName) <> Nil Then
                If FileExists(Project.DM_ProjectFullPath) Then
                Begin
                    Result := Project;
                    Exit;
                End;
    Count := 0;
    Owner := Nil;
    For I := 0 To Workspace.DM_ProjectCount - 1 Do
    Begin
        Project := Workspace.DM_Projects(I);
        If Project <> Nil Then
            If UpperCase(ExtractFileExt(Project.DM_ProjectFullPath)) = '.PRJPCB' Then
                If Project.DM_GetDocumentFromPath(Doc.DocumentName) <> Nil Then
                    If FileExists(Project.DM_ProjectFullPath) Then
                    Begin
                        Count := Count + 1;
                        Owner := Project;
                    End;
    End;
    If Count = 1 Then Result := Owner;
End;

Function RC_Support_FR_AbsolutePath(Path : String) : Boolean;
Begin
    Result := False;
    If Length(Path) >= 3 Then
        Result := ((Path[2] = ':') And (Path[3] = '\')) Or (Copy(Path, 1, 2) = '\\');
End;

{ Search live schematic instances and reuse them through native SCH Copy/Paste.
  Target: Altium 24.4.1. Missing purchasing/library metadata is not a prerequisite.
  No design document is saved. Source selections and Copy preferences are restored.
  Native processes/parameters: AD24 System/AdvSch.rcs, PLSch:Copy/Paste/ZoomSelected.
  ISch_Preferences: official Schematic API Design Objects Interfaces reference.
}

Var
    RC_Keys, RC_Titles, RC_Search, RC_Details, RC_Uses, RC_Counts : TStringList;
    RC_Paths, RC_UIDs, RC_Refs, RC_Parts, RC_Ordinals, RC_Symbols, RC_Visible : TStringList;
    RC_Sheets, RC_Seen : TStringList;

Function RC_Normalize(Value : String) : String;
Begin
    Value := UpperCase(Value);
    Value := StringReplace(Value, Chr(181), 'U', MkSet(rfReplaceAll));
    Value := StringReplace(Value, Chr(956), 'U', MkSet(rfReplaceAll));
    Value := StringReplace(Value, #9, ' ', MkSet(rfReplaceAll));
    Value := StringReplace(Value, #13, ' ', MkSet(rfReplaceAll));
    Result := StringReplace(Value, #10, ' ', MkSet(rfReplaceAll));
End;

Function RC_Matches(Query, Value : String) : Boolean;
Var Token, NextToken : String; P, Q, Start, Hit : Integer; Quantity, Found : Boolean;
Begin
    Query := Trim(RC_Normalize(Query)); Value := RC_Normalize(Value);
    Value := StringReplace(Value, ' ', '', MkSet(rfReplaceAll)); Result := True;
    While Query <> '' Do
    Begin
        P := Pos(' ', Query); If P = 0 Then P := Length(Query) + 1;
        Token := Copy(Query, 1, P - 1); Delete(Query, 1, P); Query := Trim(Query);
        { Accept both "1uF" and "1 uF". Plain numbers/MPN fragments keep their
          normal substring search; electrical quantities need a number boundary. }
        If (Pos(Copy(Token,1,1),'0123456789.') > 0) And
           (Pos(Copy(Token,Length(Token),1),'0123456789.') > 0) And (Query <> '') Then
        Begin
            Q := Pos(' ',Query); If Q = 0 Then Q := Length(Query) + 1;
            NextToken := Copy(Query,1,Q-1);
            If Pos('|' + NextToken + '|','|F|PF|NF|UF|MF|V|MV|KV|W|MW|OHM|KOHM|MOHM|HZ|KHZ|MHZ|') > 0 Then
            Begin Token := Token + NextToken; Delete(Query,1,Q); Query := Trim(Query); End;
        End;
        Quantity := (Pos(Copy(Token,1,1),'0123456789.') > 0) And
                    (Pos(Copy(Token,Length(Token),1),'ABCDEFGHIJKLMNOPQRSTUVWXYZ') > 0);
        If Not Quantity Then Found := Pos(Token,Value) > 0
        Else
        Begin
            Start := 1; Found := False;
            While Start <= Length(Value) Do
            Begin
                Hit := Pos(Token,Copy(Value,Start,Length(Value))); If Hit = 0 Then Break;
                Hit := Hit + Start - 1;
                If Hit = 1 Then Found := True
                Else Found := Pos(Copy(Value,Hit-1,1),'0123456789.,') = 0;
                If Found Then Break;
                Start := Hit + 1;
            End;
        End;
        If Not Found Then Begin Result := False; Exit; End;
    End;
End;

Function RC_Resolve(Params : TStringList; Value : String) : String;
Var Seen : TStringList; Name, NextValue : String;
Begin
    Result := Value; Seen := TStringList.Create;
    Try
        While (Length(Trim(Value)) > 1) And (Copy(Trim(Value), 1, 1) = '=') Do
        Begin
            Name := Trim(Copy(Trim(Value), 2, Length(Value)));
            If Seen.IndexOf(UpperCase(Name)) >= 0 Then Exit;
            Seen.Add(UpperCase(Name));
            NextValue := Params.Values[Name]; If NextValue = '' Then Exit;
            Value := NextValue; Result := Value;
        End;
    Finally Seen.Free; End;
End;

Function RC_Alias(Params : TStringList; Names : String) : String;
Var P : Integer; Name : String;
Begin
    Result := '';
    While Names <> '' Do
    Begin
        P := Pos('|', Names); If P = 0 Then P := Length(Names) + 1;
        Name := Copy(Names, 1, P - 1); Delete(Names, 1, P);
        Result := Trim(RC_Resolve(Params, Params.Values[Name]));
        If Result <> '' Then Exit;
    End;
End;

Procedure RC_Init(InternalCall : Boolean);
Begin
    RC_Keys := TStringList.Create; RC_Titles := TStringList.Create;
    RC_Search := TStringList.Create; RC_Details := TStringList.Create;
    RC_Uses := TStringList.Create; RC_Counts := TStringList.Create;
    RC_Paths := TStringList.Create; RC_UIDs := TStringList.Create;
    RC_Refs := TStringList.Create; RC_Parts := TStringList.Create;
    RC_Ordinals := TStringList.Create; RC_Symbols := TStringList.Create;
    RC_Visible := TStringList.Create; RC_Sheets := TStringList.Create;
    RC_Seen := TStringList.Create;
End;

Procedure RC_Clear(InternalCall : Boolean);
Begin
    RC_Keys.Clear; RC_Titles.Clear; RC_Search.Clear; RC_Details.Clear;
    RC_Uses.Clear; RC_Counts.Clear; RC_Paths.Clear; RC_UIDs.Clear;
    RC_Refs.Clear; RC_Parts.Clear; RC_Ordinals.Clear; RC_Symbols.Clear; RC_Visible.Clear;
    RC_Sheets.Clear; RC_Seen.Clear;
End;

Procedure RC_Free(InternalCall : Boolean);
Begin
    RC_Keys.Free; RC_Titles.Free; RC_Search.Free; RC_Details.Free;
    RC_Uses.Free; RC_Counts.Free; RC_Paths.Free; RC_UIDs.Free;
    RC_Refs.Free; RC_Parts.Free; RC_Ordinals.Free; RC_Symbols.Free; RC_Visible.Free;
    RC_Sheets.Free; RC_Seen.Free;
End;

Function RC_KeyField(Value : String) : String;
Begin Result := IntToStr(Length(Value)) + ':' + Value; End;

Procedure RC_AddRecord(Fields, Params : TStringList; ModelStamp, Footprints : String);
Var Value, MPN, PackageName, Maker, Rating, UseText, Key : String; GroupIndex : Integer;
Begin
    { Group using the small set of fields already read for search. No model
      traversal, sorting or per-character hashes are added for grouping. }
    MPN := RC_Alias(Params, 'Manufacturer Part Number|Manufacturer Part Number 1|Mfr Part Number|MPN|Model No.|Model Number');
    Maker := RC_Alias(Params, 'Manufacturer|Manufacturer Name|Manufacturer 1|Mfr|Mfg');
    PackageName := RC_Alias(Params, 'Package|Case|Case Size|Package Size|Package / Case');
    If PackageName = '' Then PackageName := Footprints;
    Value := RC_Alias(Params, 'Value|Capacitance|Resistance');
    If Value = '' Then Value := RC_Resolve(Params, Fields.Values['Comment']);
    If Value = '' Then Value := Fields.Values['Symbol'];
    Rating := RC_Alias(Params, 'Voltage Rating|Rated Voltage|Voltage') + ' ' +
        RC_Alias(Params, 'Dielectric|Temperature Coefficient') + ' ' + RC_Alias(Params, 'Tolerance');
    UseText := Fields.Values['Ref'] + ' - ' + ExtractFileName(Fields.Values['Path']);
    Key := RC_KeyField(Value) + RC_KeyField(MPN) + RC_KeyField(Maker) + RC_KeyField(PackageName) +
        RC_KeyField(Rating) + RC_KeyField(Footprints) + RC_KeyField(Fields.Values['Symbol']) +
        RC_KeyField(Fields.Values['Part']) + RC_KeyField(Fields.Values['Description']) + RC_KeyField(ModelStamp);
    If Fields.Values['Incomplete'] <> '' Then
        Key := Key + RC_KeyField(Fields.Values['Path']) + RC_KeyField(Fields.Values['Ordinal']);
    GroupIndex := RC_Keys.IndexOf(Key);
    If GroupIndex >= 0 Then
    Begin
        RC_Counts[GroupIndex] := IntToStr(StrToInt(RC_Counts[GroupIndex]) + 1);
        If Pos(#13#10 + UseText + #13#10, #13#10 + RC_Uses[GroupIndex] + #13#10) = 0 Then
            RC_Uses[GroupIndex] := RC_Uses[GroupIndex] + #13#10 + UseText;
        RC_Search[GroupIndex] := RC_Search[GroupIndex] + ' ' + RC_Normalize(UseText);
        Exit;
    End;
    RC_Keys.Add(Key); RC_Counts.Add('1'); RC_Uses.Add(UseText);
    RC_Paths.Add(Fields.Values['Path']); RC_UIDs.Add(Fields.Values['UID']);
    RC_Refs.Add(Fields.Values['Ref']); RC_Parts.Add(Fields.Values['Part']);
    RC_Ordinals.Add(Fields.Values['Ordinal']); RC_Symbols.Add(Fields.Values['Symbol']);
    RC_Titles.Add(Value + ' | ' + PackageName + ' | ' + MPN);
    RC_Details.Add('Value / Comment: ' + Value + #13#10 + 'MPN: ' + MPN + #13#10 +
        'Manufacturer: ' + Maker + #13#10 + 'Package: ' + PackageName + #13#10 +
        'Rating: ' + Trim(Rating) + #13#10 + 'Description: ' + Fields.Values['Description']);
    RC_Search.Add(RC_Normalize(Value + ' ' + MPN + ' ' + Maker + ' ' + PackageName + ' ' +
        Footprints + ' ' + Rating + ' ' + Fields.Values['Ref'] + ' ' + Fields.Values['Symbol'] + ' ' +
        Fields.Values['Description'] + ' ' + Fields.Values['Comment'] + ' ' + Fields.Values['Path']));
End;

{ BEGIN ReuseNative }
Var
    RC_Destination : ISch_Document;
    RC_Project : IProject;
    RC_Active, RC_Loading : Boolean;
    RC_LogLines : TStringList;
    RC_Stage, RC_LogPath : String;
    RC_Warnings, RC_Total, RC_NextSheet : Integer;
    RC_Queued : Boolean;

Procedure RC_Log(Text : String);
Begin
    If RC_LogLines = Nil Then Exit;
    RC_LogLines.Add(Text);
    Try If RC_LogPath <> '' Then RC_LogLines.SaveToFile(RC_LogPath); Except End;
End;

Function RC_ActiveDocument(InternalCall : Boolean) : ISch_Document;
Var Workspace : IWorkspace; Focused : IDocument;
Begin
    Result := SchServer.GetCurrentSchDocument; Workspace := GetWorkspace;
    If Workspace <> Nil Then
    Begin
        Focused := Workspace.DM_FocusedDocument;
        If Focused <> Nil Then
            If UpperCase(ExtractFileExt(Focused.DM_FullPath)) = '.SCHDOC' Then
                Result := SchServer.GetSchDocumentByPath(Focused.DM_FullPath);
    End;
    If Result <> Nil Then
        If UpperCase(ExtractFileExt(Result.DocumentName)) <> '.SCHDOC' Then Result := Nil;
End;

Function RC_IsSearchParameter(Name : String) : Boolean;
Begin
    Result := Pos('|' + UpperCase(Trim(Name)) + '|',
        '|VALUE|CAPACITANCE|RESISTANCE|MANUFACTURER PART NUMBER|MANUFACTURER PART NUMBER 1|MFR PART NUMBER|MPN|MODEL NO.|MODEL NUMBER|MANUFACTURER|MANUFACTURER NAME|MANUFACTURER 1|MFR|MFG|PACKAGE|CASE|CASE SIZE|PACKAGE SIZE|PACKAGE / CASE|VOLTAGE RATING|RATED VOLTAGE|VOLTAGE|DIELECTRIC|TEMPERATURE COEFFICIENT|TOLERANCE|') > 0;
End;

Procedure RC_ReadComponent(Comp : ISch_Component; Path : String; Ordinal : Integer);
Var Params, Fields : TStringList; It : ISch_Iterator;
    Param : ISch_Parameter; Model : ISch_Implementation; Name, Footprint, CommentName : String;
Begin
    Params := TStringList.Create; Fields := TStringList.Create;
    Try
        Fields.Values['Path'] := Path; Fields.Values['Ordinal'] := IntToStr(Ordinal);
        Fields.Values['Ref'] := Comp.Designator.Text; Fields.Values['UID'] := Comp.UniqueId;
        Fields.Values['Part'] := IntToStr(Comp.CurrentPartID);
        Fields.Values['Symbol'] := Comp.LibReference; Fields.Values['Comment'] := Comp.Comment.Text;
        Try Fields.Values['Description'] := Comp.ComponentDescription; Except End;
        CommentName := Trim(Fields.Values['Comment']);
        If Copy(CommentName,1,1) = '=' Then Delete(CommentName,1,1) Else CommentName := '';
        It := Comp.SchIterator_Create;
        If It <> Nil Then
        Try
            It.SetState_IterationDepth(eIterateFirstLevel); It.AddFilter_ObjectSet(MkSet(eParameter));
            Param := It.FirstSchObject;
            While Param <> Nil Do
            Begin
                Name := Param.Name;
                If RC_IsSearchParameter(Name) Or (UpperCase(Name) = UpperCase(CommentName)) Then
                    Try Params.Values[Name] := Param.Text; Except End;
                Param := It.NextSchObject;
            End;
        Finally Comp.SchIterator_Destroy(It); End;
        Footprint := '';
        If RC_Alias(Params, 'Package|Case|Case Size|Package Size|Package / Case') = '' Then
        Begin
            It := Comp.SchIterator_Create;
            If It <> Nil Then
            Try
                It.AddFilter_ObjectSet(MkSet(eImplementation)); Model := It.FirstSchObject;
                While Model <> Nil Do
                Begin
                    If RC_Support_FL_IsFootprint(Model) Then
                    Begin
                        If Footprint = '' Then Footprint := Model.ModelName;
                        If Model.IsCurrent Then Begin Footprint := Model.ModelName; Break; End;
                    End;
                    Model := It.NextSchObject;
                End;
            Finally Comp.SchIterator_Destroy(It); End;
        End;
        RC_AddRecord(Fields, Params, '', Footprint); RC_Total := RC_Total + 1;
    Finally Params.Free; Fields.Free; End;
End;

Procedure RC_ReadSheet(Path : String; Seen : TStringList);
Var View : IServerDocument; Doc : ISch_Document; It : ISch_Iterator;
    Comp : ISch_Component; Owned : Boolean; Ordinal : Integer;
Begin
    If UpperCase(ExtractFileExt(Path)) <> '.SCHDOC' Then Exit;
    Path := ExpandFileName(Path);
    If Seen.IndexOf(UpperCase(Path)) >= 0 Then Exit;
    Seen.Add(UpperCase(Path)); View := Client.GetDocumentByPath(Path); Owned := View = Nil;
    RC_Stage := 'Read sheet ' + Path; RC_Log(RC_Stage);
    Try
      Try
        If UpperCase(Path) = UpperCase(RC_Destination.DocumentName) Then Doc := RC_Destination
        Else
        Begin
            If Owned Then View := Client.OpenDocumentShowOrHide('SCH', Path, False);
            If View = Nil Then Begin RC_Warnings := RC_Warnings + 1; RC_Log('SKIP unavailable sheet'); Exit; End;
            Doc := SchServer.GetSchDocumentByPath(Path);
            If Doc = Nil Then
            Begin Client.ShowDocument(View); Doc := SchServer.GetSchDocumentByPath(Path); End;
        End;
        If Doc = Nil Then Begin RC_Warnings := RC_Warnings + 1; Exit; End;
        It := Doc.SchIterator_Create;
        If It = Nil Then Begin RC_Warnings := RC_Warnings + 1; Exit; End;
        Try
            It.AddFilter_ObjectSet(MkSet(eSchComponent)); Comp := It.FirstSchObject; Ordinal := 0;
            While Comp <> Nil Do
            Begin
                Try RC_ReadComponent(Comp, Path, Ordinal);
                Except RC_Warnings := RC_Warnings + 1; RC_Log('SKIP unreadable instance ' + IntToStr(Ordinal)); End;
                Ordinal := Ordinal + 1; Comp := It.NextSchObject;
            End;
        Finally Doc.SchIterator_Destroy(It); End;
      Except RC_Warnings := RC_Warnings + 1; RC_Log('SKIP sheet read failed'); End;
    Finally
        If Owned And (View <> Nil) Then If Not View.Modified Then Client.CloseDocument(View);
    End;
End;

Function RC_FindSource(Doc : ISch_Document; Index : Integer) : ISch_Component;
Var It : ISch_Iterator; Comp, Fallback : ISch_Component; Ordinal : Integer;
Begin
    Result := Nil; Fallback := Nil; It := Doc.SchIterator_Create;
    If It = Nil Then Exit;
    Try
        It.AddFilter_ObjectSet(MkSet(eSchComponent)); Comp := It.FirstSchObject; Ordinal := 0;
        While Comp <> Nil Do
        Begin
            If (Comp.Designator.Text = RC_Refs[Index]) And (Comp.LibReference = RC_Symbols[Index]) And
               (IntToStr(Comp.CurrentPartID) = RC_Parts[Index]) Then
            Begin
                If (RC_UIDs[Index] <> '') And (Comp.UniqueId = RC_UIDs[Index]) Then Begin Result := Comp; Exit; End;
                If IntToStr(Ordinal) = RC_Ordinals[Index] Then Fallback := Comp;
            End;
            Ordinal := Ordinal + 1; Comp := It.NextSchObject;
        End;
        Result := Fallback;
    Finally Doc.SchIterator_Destroy(It); End;
End;

Function RC_SelectedGroup(InternalCall : Boolean) : Integer;
Var Row : Integer;
Begin
    Result := -1;
    Row := TListBox(ReuseComponentForm.FindComponent('Results')).ItemIndex;
    If (Row >= 0) And (Row < RC_Visible.Count) Then Result := StrToInt(RC_Visible[Row]);
End;

Procedure RC_ShowDetails(InternalCall : Boolean);
Var I : Integer;
Begin
    I := RC_SelectedGroup(True);
    TButton(ReuseComponentForm.FindComponent('PlaceButton')).Enabled := I >= 0;
    TButton(ReuseComponentForm.FindComponent('LocateButton')).Enabled := I >= 0;
    If I < 0 Then TMemo(ReuseComponentForm.FindComponent('Details')).Lines.Text := ''
    Else TMemo(ReuseComponentForm.FindComponent('Details')).Lines.Text := RC_Details[I] + #13#10 +
        'Used ' + RC_Counts[I] + ' time(s):' + #13#10 + RC_Uses[I];
End;

Procedure RC_Filter(InternalCall : Boolean);
Var List : TListBox; Query, Status : String; I, Previous, SelectedRow : Integer;
Begin
    List := TListBox(ReuseComponentForm.FindComponent('Results'));
    Query := TEdit(ReuseComponentForm.FindComponent('Query')).Text;
    Previous := RC_SelectedGroup(True); SelectedRow := -1;
    List.Items.Clear; RC_Visible.Clear;
    For I := 0 To RC_Keys.Count - 1 Do
        If RC_Matches(Query, RC_Search[I]) Then
        Begin
            RC_Visible.Add(IntToStr(I));
            List.Items.Add(RC_Titles[I] + ' | ' + RC_Counts[I] + ' used');
            If I = Previous Then SelectedRow := List.Items.Count - 1;
        End;
    If SelectedRow >= 0 Then List.ItemIndex := SelectedRow
    Else If List.Items.Count > 0 Then List.ItemIndex := 0;
    Status := IntToStr(RC_Visible.Count) + ' part types shown / ' + IntToStr(RC_Total) + ' placed components';
    If RC_Warnings > 0 Then Status := Status + '. Skipped ' + IntToStr(RC_Warnings) + ' unreadable item(s).';
    If RC_Queued And (RC_NextSheet < RC_Sheets.Count) Then Status := Status + ' - loading sheets ' + IntToStr(RC_NextSheet) + '/' + IntToStr(RC_Sheets.Count);
    TLabel(ReuseComponentForm.FindComponent('Status')).Caption := Status;
    RC_ShowDetails(True);
End;

Procedure RC_QueueSheet(Path : String);
Begin
    If UpperCase(ExtractFileExt(Path)) <> '.SCHDOC' Then Exit;
    Path := ExpandFileName(Path);
    If RC_Sheets.IndexOf(Path) < 0 Then RC_Sheets.Add(Path);
End;

Procedure RC_Rebuild(InternalCall : Boolean);
Var Sections : TStringList; Ini : TIniFile; Entry : IDocument;
    I, Owners : Integer; Path, Folder : String;
Begin
    RC_Loading := True; RC_Clear(True); RC_Warnings := 0; RC_Total := 0; RC_NextSheet := 0;
    Sections := TStringList.Create;
    Try
        RC_QueueSheet(RC_Destination.DocumentName);
        RC_Project := RC_Support_FL_FindOwningProject(RC_Destination, Owners);
        If (RC_Project <> Nil) And (TComboBox(ReuseComponentForm.FindComponent('Scope')).ItemIndex = 0) Then
        Begin
            For I := 0 To RC_Project.DM_LogicalDocumentCount - 1 Do
            Begin
                Entry := RC_Project.DM_LogicalDocuments(I);
                If Entry <> Nil Then RC_QueueSheet(Entry.DM_FullPath);
            End;
            Folder := ExtractFilePath(RC_Project.DM_ProjectFullPath);
            Try
                Ini := TIniFile.Create(RC_Project.DM_ProjectFullPath);
                Try
                    Ini.ReadSections(Sections);
                    For I := 0 To Sections.Count - 1 Do
                    Begin
                        Path := Ini.ReadString(Sections[I], 'DocumentPath', '');
                        If UpperCase(ExtractFileExt(Path)) = '.SCHDOC' Then
                        Begin
                            If Not RC_Support_FR_AbsolutePath(Path) Then Path := Folder + Path;
                            If RC_Project.DM_GetDocumentFromPath(Path) <> Nil Then RC_QueueSheet(Path);
                        End;
                    End;
                Finally Ini.Free; End;
            Except RC_Log('Using live project sheets'); End;
        End;
    Finally Sections.Free; RC_Loading := False; RC_Queued := True; End;
End;

Procedure RC_LoadTick(Sender : TObject);
Begin
    TTimer(ReuseComponentForm.FindComponent('LoadTimer')).Enabled := False;
    If Not RC_Active Then Exit;
    Try
        If Not RC_Queued Then RC_Rebuild(True);
        If RC_NextSheet < RC_Sheets.Count Then
        Begin
            RC_Loading := True;
            Try RC_ReadSheet(RC_Sheets[RC_NextSheet], RC_Seen);
            Finally RC_Loading := False; RC_NextSheet := RC_NextSheet + 1; End;
        End;
        RC_Filter(True);
        If RC_NextSheet >= RC_Sheets.Count Then RC_Log('READY ' + IntToStr(RC_Total) + ' components ' + DateTimeToStr(Now));
    Except RC_Loading := False; RC_Log('Load stopped; loaded instances remain usable'); End;
    If RC_Active And (RC_NextSheet < RC_Sheets.Count) Then
        TTimer(ReuseComponentForm.FindComponent('LoadTimer')).Enabled := True;
End;

Procedure RC_QueryChanged(Sender : TObject);
Begin If RC_Active And Not RC_Loading Then RC_Filter(True); End;

Procedure RC_ScopeChanged(Sender : TObject);
Begin
    If Not RC_Active Or RC_Loading Then Exit;
    RC_Queued := False;
    TTimer(ReuseComponentForm.FindComponent('LoadTimer')).Enabled := True;
End;

Procedure RC_ResultClicked(Sender : TObject);
Begin
    If RC_Active And Not RC_Loading Then
    RC_ShowDetails(True);
End;

Procedure RC_PlaceClick(Sender : TObject);
Begin
    If Not RC_Active Then Exit;
    If RC_SelectedGroup(True) >= 0 Then ReuseComponentForm.ModalResult := 6;
End;

Procedure RC_LocateClick(Sender : TObject);
Begin
    If Not RC_Active Then Exit;
    If RC_SelectedGroup(True) >= 0 Then ReuseComponentForm.ModalResult := 7;
End;

Procedure RC_SetSelection(Doc : ISch_Document; Comp : ISch_Component; Saved : TStringList; Restore : Boolean);
Var It : ISch_Iterator; Obj : ISch_GraphicalObject; I : Integer;
Begin
    It := Doc.SchIterator_Create; If It = Nil Then Exit;
    Try
        It.SetState_IterationDepth(eIterateFirstLevel); Obj := It.FirstSchObject; I := 0;
        While Obj <> Nil Do
        Begin
            { Copy does not add/remove source objects, so first-level iterator
              order stays fixed. AD24 object addresses are opaque wrappers. }
            If Restore Then
            Begin
                If I < Saved.Count Then Obj.Selection := Saved[I] = '1';
            End
            Else
            Begin
                { DelphiScript can expose True as -1 rather than Ord(True)=1. }
                If Obj.Selection Then Saved.Add('1') Else Saved.Add('0');
                Obj.Selection := False;
            End;
            I := I + 1; Obj := It.NextSchObject;
        End;
        If Not Restore Then Comp.Selection := True;
    Finally Doc.SchIterator_Destroy(It); End;
    Doc.GraphicallyInvalidate;
End;

Procedure RC_UseSource(Index, Action : Integer);
Var SourceView, DestinationView : IServerDocument; Doc : ISch_Document; Comp : ISch_Component;
    Prefs : ISch_Preferences; Saved : TStringList; Owned, OldReference, OldTemplate, CopyStarted, Copied : Boolean;
Begin
    RC_Stage := 'Open selected source'; RC_Log(RC_Stage);
    SourceView := Client.GetDocumentByPath(RC_Paths[Index]); Owned := SourceView = Nil;
    DestinationView := Client.GetDocumentByPath(RC_Destination.DocumentName);
    Saved := TStringList.Create; CopyStarted := False; Copied := False;
    Try
      Try
        If Owned Then SourceView := Client.OpenDocumentShowOrHide('SCH', RC_Paths[Index], False);
        If SourceView = Nil Then Begin ShowMessage('Cannot open the source sheet. The remaining search results can still be used.'); Exit; End;
        Client.ShowDocument(SourceView); Doc := SchServer.GetSchDocumentByPath(RC_Paths[Index]);
        If Doc = Nil Then Exit;
        Comp := RC_FindSource(Doc, Index);
        If Comp = Nil Then Begin ShowMessage('The source component changed. Run Reuse Component again to refresh the list.'); Exit; End;
        If Action = 7 Then
        Begin
            RC_SetSelection(Doc, Comp, Saved, False); Owned := False;
            ResetParameters; AddStringParameter('Object', 'Selected'); RunProcess('Sch:Zoom');
            RC_Log('LOCATED ' + RC_Refs[Index]); Exit;
        End;
        RC_Stage := 'Copy selected component'; RC_Log(RC_Stage);
        Prefs := SchServer.GetState_SchPreferences;
        OldReference := Prefs.Get_SelectionReference; OldTemplate := Prefs.Get_AddTemplateToClipBoard;
        Try
            CopyStarted := True;
            RC_SetSelection(Doc, Comp, Saved, False);
            Prefs.Set_SelectionReference(False); Prefs.Set_AddTemplateToClipBoard(False);
            ResetParameters; AddStringParameter('ClipboardMode', 'ClipboardRing'); RunProcess('Sch:Copy');
            Copied := True; RC_Log('COPIED ' + RC_Refs[Index]);
        Finally
            Try
                If CopyStarted Then RC_SetSelection(Doc, Comp, Saved, True);
            Finally
                Try Prefs.Set_SelectionReference(OldReference);
                Finally Prefs.Set_AddTemplateToClipBoard(OldTemplate); End;
            End;
        End;
      Finally
        If (Action <> 7) Or Owned Then
            If DestinationView <> Nil Then Client.ShowDocument(DestinationView);
        If Owned And (SourceView <> Nil) Then
            If Not SourceView.Modified Then Client.CloseDocument(SourceView);
      End;
      If Copied Then
      Begin
          RC_Stage := 'Paste into destination sheet'; RC_Log(RC_Stage);
          ResetParameters; RunProcess('Sch:Paste'); RC_Log('PASTE command returned');
      End;
    Finally Saved.Free; End;
End;

Procedure RC_ReuseComponent(InternalCall : Boolean);
Var Action, Index : Integer;
Begin
    If RC_Active Then Exit;
    If (SchServer = Nil) Or (Client = Nil) Then Exit;
    If ReuseComponentForm = Nil Then
    Begin ShowMessage('Reopen ReuseComponent.PrjScr or AltiumScriptTools.PrjScr to load Reuse Component.'); Exit; End;
    If (ReuseComponentForm.FindComponent('Query') = Nil) Or
       (ReuseComponentForm.FindComponent('LoadTimer') = Nil) Then
    Begin ShowMessage('Reopen the script project to load the Reuse Component search form.'); Exit; End;
    RC_Destination := RC_ActiveDocument(True);
    If RC_Destination = Nil Then Begin ShowMessage('Open the schematic sheet where you want to place a component.'); Exit; End;
    RC_LogLines := TStringList.Create;
    RC_LogPath := ExtractFilePath(RC_Destination.DocumentName) + 'ReuseComponent-debug.log';
    RC_Init(True); RC_Stage := 'Read project components';
    Try
      Try
        RC_Log('Reuse Component v0.4 - ' + DateTimeToStr(Now));
        RC_Project := Nil;
        RC_Active := False; RC_Loading := True;
        TEdit(ReuseComponentForm.FindComponent('Query')).Text := '';
        TComboBox(ReuseComponentForm.FindComponent('Scope')).ItemIndex := 0;
        RC_Queued := False; RC_NextSheet := 0; RC_Active := True; RC_Loading := False;
        RC_Filter(True);
        TLabel(ReuseComponentForm.FindComponent('Status')).Caption := 'Loading components...';
        Repeat
            RC_Active := True;
            TTimer(ReuseComponentForm.FindComponent('LoadTimer')).Enabled :=
                (Not RC_Queued) Or (RC_NextSheet < RC_Sheets.Count);
            ReuseComponentForm.ModalResult := 0; ReuseComponentForm.ShowModal;
            Action := ReuseComponentForm.ModalResult; Index := RC_SelectedGroup(True);
            RC_Active := False;
            TTimer(ReuseComponentForm.FindComponent('LoadTimer')).Enabled := False;
            If (Index >= 0) And ((Action = 6) Or (Action = 7)) Then RC_UseSource(Index, Action);
            { Native Paste returns when placement ends. Keep the loaded results,
              query and selection for the next choice; Locate leaves the source open. }
        Until (Action <> 6) Or (Index < 0);
      Except
        RC_Log('FAILED at ' + RC_Stage);
        ShowMessage('Reuse Component stopped at: ' + RC_Stage + #13#10 + 'Log: ' + RC_LogPath);
      End;
    Finally
        TTimer(ReuseComponentForm.FindComponent('LoadTimer')).Enabled := False;
        RC_Active := False; RC_Loading := False; RC_Project := Nil; RC_Destination := Nil;
        RC_Free(True); RC_LogLines.Free; RC_LogLines := Nil;
    End;
End;

Procedure ReuseComponent_01_Main;
Begin
    RC_ReuseComponent(True);
End;

