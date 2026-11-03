object ReuseComponentForm: TReuseComponentForm
  Caption = 'ReuseComponent'
  ClientWidth = 940
  ClientHeight = 620
  object SearchLabel: TLabel
    Left = 16
    Top = 16
    Caption = 'Search value, MPN, package or designator'
  end
  object Query: TEdit
    Left = 16
    Top = 40
    Width = 648
    Height = 25
    OnChange = RC_QueryChanged
    TabOrder = 0
  end
  object Scope: TComboBox
    Left = 680
    Top = 40
    Width = 244
    Height = 25
    Style = csDropDownList
    ItemIndex = 0
    Text = 'Current project'
    Items.Strings = (
      'Current project'
      'Current sheet')
    OnChange = RC_ScopeChanged
    TabOrder = 1
  end
  object ResultsLabel: TLabel
    Left = 16
    Top = 80
    Caption = 'Value / Comment  |  Package  |  MPN  |  Used'
  end
  object Results: TListBox
    Left = 16
    Top = 104
    Width = 908
    Height = 228
    ItemHeight = 18
    OnClick = RC_ResultClicked
    OnDblClick = RC_PlaceClick
    TabOrder = 2
  end
  object Details: TMemo
    Left = 16
    Top = 344
    Width = 908
    Height = 182
    ReadOnly = True
    ScrollBars = ssBoth
    WordWrap = False
    TabOrder = 3
  end
  object Status: TLabel
    Left = 16
    Top = 536
    Width = 908
    Height = 32
    AutoSize = False
    WordWrap = True
    Caption = ''
  end
  object LocateButton: TButton
    Left = 552
    Top = 576
    Width = 112
    Height = 30
    Caption = 'Locate'
    OnClick = RC_LocateClick
    TabOrder = 4
  end
  object PlaceButton: TButton
    Left = 680
    Top = 576
    Width = 116
    Height = 30
    Caption = 'Place copy'
    Default = True
    OnClick = RC_PlaceClick
    TabOrder = 5
  end
  object CancelButton: TButton
    Left = 812
    Top = 576
    Width = 112
    Height = 30
    Caption = 'Cancel'
    Cancel = True
    ModalResult = 2
    TabOrder = 6
  end
  object LoadTimer: TTimer
    Enabled = False
    Interval = 10
    OnTimer = RC_LoadTick
    Left = 896
    Top = 8
  end
end
