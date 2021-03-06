{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2014 by Maciej Izak (hnb)
    member of the Free Sparta development team (http://freesparta.com)

    Copyright(c) 2004-2014 DaThoX

    It contains the Free Pascal generics library

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

unit Generics.Collections;

{$MODE DELPHI}{$H+}
{$MACRO ON}
{$COPERATORS ON}
{$DEFINE CUSTOM_DICTIONARY_CONSTRAINTS := TKey, TValue, THashFactory}
{$DEFINE OPEN_ADDRESSING_CONSTRAINTS := TKey, TValue, THashFactory, TProbeSequence}
{$DEFINE CUCKOO_CONSTRAINTS := TKey, TValue, THashFactory, TCuckooCfg}
{$DEFINE TREE_CONSTRAINTS := TKey, TValue, TInfo}
{$WARNINGS OFF}
{$HINTS OFF}
{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

interface

uses
    RtlConsts, Classes, SysUtils, Generics.MemoryExpanders, Generics.Defaults,
    Generics.Helpers, Generics.Strings;

{ FPC BUGS related to Generics.* (54 bugs, 19 fixed)
  REGRESSION: 26483, 26481
  FIXED REGRESSION: 26480, 26482

  CRITICAL: 24848(!!!), 24872(!), 25607(!), 26030, 25917, 25918, 25620, 24283, 24254, 24287 (Related to? 24872)
  IMPORTANT: 23862(!), 24097, 24285, 24286 (Similar to? 24285), 24098, 24609 (RTL inconsistency), 24534,
             25606, 25614, 26177, 26195
  OTHER: 26484, 24073, 24463, 25593, 25596, 25597, 25602, 26181 (or MYBAD?)
  CLOSED BUT IMO STILL TO FIX: 25601(!), 25594
  FIXED: 25610(!), 24064, 24071, 24282, 24458, 24867, 24871, 25604, 25600, 25605, 25598, 25603, 25929, 26176, 26180,
         26193, 24072
  MYBAD: 24963, 25599
}

{ LAZARUS BUGS related to Generics.* (7 bugs, 0 fixed)
  CRITICAL: 25613
  OTHER: 25595, 25612, 25615, 25617, 25618, 25619
}

{.$define EXTRA_WARNINGS}

type
  EAVLTree = class(Exception);
  EIndexedAVLTree = class(EAVLTree);

  TDuplicates = Classes.TDuplicates;

  {$ifdef VER3_0_0}
  TArray<T> = array of T;
  {$endif}

  // bug #24254 workaround
  // should be TArray = record class procedure Sort<T>(...) etc.
  TBinarySearchResult = record
    FoundIndex, CandidateIndex: SizeInt;
    CompareResult: SizeInt;
  end;

  TCustomArrayHelper<T> = class abstract
  private
    type
      // bug #24282
      TComparerBugHack = TComparer<T>;
  protected
    // modified QuickSort from classes\lists.inc
    class procedure QuickSort(var AValues: array of T; ALeft, ARight: SizeInt; const AComparer: IComparer<T>);
      virtual; abstract;
  public
    class procedure Sort(var AValues: array of T); overload;
    class procedure Sort(var AValues: array of T;
      const AComparer: IComparer<T>);   overload;
    class procedure Sort(var AValues: array of T;
      const AComparer: IComparer<T>; AIndex, ACount: SizeInt); overload;

    class function BinarySearch(constref AValues: array of T; constref AItem: T;
      out ASearchResult: TBinarySearchResult; const AComparer: IComparer<T>;
      AIndex, ACount: SizeInt): Boolean; virtual; abstract; overload;
    class function BinarySearch(constref AValues: array of T; constref AItem: T;
      out AFoundIndex: SizeInt; const AComparer: IComparer<T>;
      AIndex, ACount: SizeInt): Boolean; overload;
    class function BinarySearch(constref AValues: array of T; constref AItem: T;
      out AFoundIndex: SizeInt; const AComparer: IComparer<T>): Boolean; overload;
    class function BinarySearch(constref AValues: array of T; constref AItem: T;
      out AFoundIndex: SizeInt): Boolean; overload;
    class function BinarySearch(constref AValues: array of T; constref AItem: T;
      out ASearchResult: TBinarySearchResult; const AComparer: IComparer<T>): Boolean; overload;
    class function BinarySearch(constref AValues: array of T; constref AItem: T;
      out ASearchResult: TBinarySearchResult): Boolean; overload;
  end {$ifdef EXTRA_WARNINGS}experimental{$endif}; // will be renamed to TCustomArray (bug #24254)

  TArrayHelper<T> = class(TCustomArrayHelper<T>)
  protected
    // modified QuickSort from classes\lists.inc
    class procedure QuickSort(var AValues: array of T; ALeft, ARight: SizeInt; const AComparer: IComparer<T>); override;
  public
    class function BinarySearch(constref AValues: array of T; constref AItem: T;
      out ASearchResult: TBinarySearchResult; const AComparer: IComparer<T>;
      AIndex, ACount: SizeInt): Boolean; override; overload;
  end {$ifdef EXTRA_WARNINGS}experimental{$endif}; // will be renamed to TArray (bug #24254)

  TCollectionNotification = (cnAdded, cnRemoved, cnExtracted);
  TCollectionNotifyEvent<T> = procedure(ASender: TObject; constref AItem: T; AAction: TCollectionNotification)
    of object;

  { TEnumerator }

  TEnumerator<T> = class abstract
  protected
    function DoGetCurrent: T; virtual; abstract;
    function DoMoveNext: boolean; virtual; abstract;
  public
    property Current: T read DoGetCurrent;
    function MoveNext: boolean;
  end;

  { TEnumerable }

  TEnumerable<T> = class abstract
  protected
    function ToArrayImpl(ACount: SizeInt): TArray<T>; overload; // used by descendants
  protected
    function DoGetEnumerator: TEnumerator<T>; virtual; abstract;
  public
    function GetEnumerator: TEnumerator<T>; inline;
    function ToArray: TArray<T>; virtual; overload;
  end;

  // More info: http://stackoverflow.com/questions/5232198/about-vectors-growth
  // TODO: custom memory managers (as constraints)
  {$DEFINE CUSTOM_LIST_CAPACITY_INC := Result + Result div 2} // ~approximation to golden ratio: n = n * 1.5 }
  // {$DEFINE CUSTOM_LIST_CAPACITY_INC := Result * 2} // standard inc
  TCustomList<T> = class abstract(TEnumerable<T>)
  public type
    PT = ^T;
  protected
    type // bug #24282
      TArrayHelperBugHack = TArrayHelper<T>;
  private
    FOnNotify: TCollectionNotifyEvent<T>;
    function GetCapacity: SizeInt; inline;
  private type
    PItems = ^TItems;
    TItems = record
      FLength: SizeInt;
      FItems: array of T;
    end;
  protected
    FItems: TItems;

    function PrepareAddingItem: SizeInt; virtual;
    function PrepareAddingRange(ACount: SizeInt): SizeInt; virtual;
    procedure Notify(constref AValue: T; ACollectionNotification: TCollectionNotification); virtual;
    function DoRemove(AIndex: SizeInt; ACollectionNotification: TCollectionNotification): T; virtual;
    procedure SetCapacity(AValue: SizeInt); virtual; abstract;
    function GetCount: SizeInt; virtual;
  public
    function ToArray: TArray<T>; override; final;

    property Count: SizeInt read GetCount;
    property Capacity: SizeInt read GetCapacity write SetCapacity;
    property OnNotify: TCollectionNotifyEvent<T> read FOnNotify write FOnNotify;
  end;

  TCustomListEnumerator<T> = class abstract(TEnumerator<T>)
  private
    FList: TCustomList<T>;
    FIndex: SizeInt;
  protected
    function DoMoveNext: boolean; override;
    function DoGetCurrent: T; override;
    function GetCurrent: T; virtual;
  public
    constructor Create(AList: TCustomList<T>);
  end;

  TCustomListPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>)
  private type
    TList = TCustomList<T>; // lazarus bug workaround
  private var
    FList: TList.PItems;
    FIndex: SizeInt;
  protected
    function DoMoveNext: boolean; override;
    function DoGetCurrent: PT; override;
    function GetCurrent: PT; virtual;
  public
    constructor Create(AList: TList.PItems);
  end;

  TCustomListPointersCollection<TPointersEnumerator, T, PT> = record
  private type
    TList = TCustomList<T>; // lazarus bug workaround
  private
    function List: TList.PItems; inline;
    function GetCount: SizeInt; inline;
    function GetItem(AIndex: SizeInt): PT;
  public
    function GetEnumerator: TPointersEnumerator;
    function ToArray: TArray<PT>;
    property Count: SizeInt read GetCount;
    property Items[Index: SizeInt]: PT read GetItem; default;
  end;

  TCustomListWithPointers<T> = class(TCustomList<T>)
  private type
    TPointersEnumerator = class(TCustomListPointersEnumerator<T, PT>);
    TPointersCollection = TCustomListPointersCollection<TPointersEnumerator, T, PT>;
  public type
    PPointersCollection = ^TPointersCollection;
  private
    function GetPointers: PPointersCollection; inline;
  public
    property Ptr: PPointersCollection read GetPointers;
  end;

  TList<T> = class(TCustomListWithPointers<T>)
  private var
    FComparer: IComparer<T>;
  protected
    // bug #24287 - workaround for generics type name conflict (Identifier not found)
    // next bug workaround - for another error related to previous workaround
    // change order (method must be declared before TEnumerator declaration)
    function DoGetEnumerator: {Generics.Collections.}TEnumerator<T>; override;
  public
    // with this type declaration i found #24285, #24285
    type
      // bug workaround
      TEnumerator = class(TCustomListEnumerator<T>);

    function GetEnumerator: TEnumerator; reintroduce;
  protected
    procedure SetCapacity(AValue: SizeInt); override;
    procedure SetCount(AValue: SizeInt);
    procedure InitializeList; virtual;
    procedure InternalInsert(AIndex: SizeInt; constref AValue: T);
  private
    function GetItem(AIndex: SizeInt): T;
    procedure SetItem(AIndex: SizeInt; const AValue: T);
  public
    constructor Create; overload;
    constructor Create(const AComparer: IComparer<T>); overload;
    constructor Create(ACollection: TEnumerable<T>); overload;
    destructor Destroy; override;

    function Add(constref AValue: T): SizeInt; virtual;
    procedure AddRange(constref AValues: array of T); virtual; overload;
    procedure AddRange(const AEnumerable: IEnumerable<T>); overload;
    procedure AddRange(AEnumerable: TEnumerable<T>); overload;

    procedure Insert(AIndex: SizeInt; constref AValue: T); virtual;
    procedure InsertRange(AIndex: SizeInt; constref AValues: array of T); virtual; overload;
    procedure InsertRange(AIndex: SizeInt; const AEnumerable: IEnumerable<T>); overload;
    procedure InsertRange(AIndex: SizeInt; const AEnumerable: TEnumerable<T>); overload;

    function Remove(constref AValue: T): SizeInt;
    procedure Delete(AIndex: SizeInt); inline;
    procedure DeleteRange(AIndex, ACount: SizeInt);
    function ExtractIndex(const AIndex: SizeInt): T; overload;
    function Extract(constref AValue: T): T; overload;

    procedure Exchange(AIndex1, AIndex2: SizeInt); virtual;
    procedure Move(AIndex, ANewIndex: SizeInt); virtual;

    function First: T; inline;
    function Last: T; inline;

    procedure Clear;

    function Contains(constref AValue: T): Boolean; inline;
    function IndexOf(constref AValue: T): SizeInt; virtual;
    function LastIndexOf(constref AValue: T): SizeInt; virtual;

    procedure Reverse;

    procedure TrimExcess;

    procedure Sort; overload;
    procedure Sort(const AComparer: IComparer<T>); overload;
    function BinarySearch(constref AItem: T; out AIndex: SizeInt): Boolean; overload;
    function BinarySearch(constref AItem: T; out AIndex: SizeInt; const AComparer: IComparer<T>): Boolean; overload;

    property Count: SizeInt read FItems.FLength write SetCount;
    property Items[Index: SizeInt]: T read GetItem write SetItem; default;
  end;

  TCollectionSortStyle = (cssNone,cssUser,cssAuto);
  TCollectionSortStyles = Set of TCollectionSortStyle;

  TSortedList<T> = class(TList<T>)
  private
    FDuplicates: TDuplicates;
    FSortStyle: TCollectionSortStyle;
    function GetSorted: boolean;
    procedure SetSorted(AValue: boolean);
    procedure SetSortStyle(AValue: TCollectionSortStyle);
  protected
    procedure InitializeList; override;
  public
    function Add(constref AValue: T): SizeInt; override; overload;
    procedure AddRange(constref AValues: array of T); override; overload;
    procedure Insert(AIndex: SizeInt; constref AValue: T); override;
    procedure Exchange(AIndex1, AIndex2: SizeInt); override;
    procedure Move(AIndex, ANewIndex: SizeInt); override;
    procedure InsertRange(AIndex: SizeInt; constref AValues: array of T); override; overload;
    property Duplicates: TDuplicates read FDuplicates write FDuplicates;
    property Sorted: Boolean read GetSorted write SetSorted;
    property SortStyle: TCollectionSortStyle read FSortStyle write SetSortStyle;

    function ConsistencyCheck(ARaiseException: boolean = true): boolean; virtual;
  end;

  TThreadList<T> = class
  private
    FList: TList<T>;
    FDuplicates: TDuplicates;
    FLock: TRTLCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Add(constref AValue: T);
    procedure Remove(constref AValue: T);
    procedure Clear;

    function LockList: TList<T>;
    procedure UnlockList; inline;

    property Duplicates: TDuplicates read FDuplicates write FDuplicates;
  end;

  TQueuePointersEnumerator<T, PT> = class abstract(TEnumerator<PT>)
  private type
    TList = TCustomList<T>; // lazarus bug workaround
  private var
    FList: TList.PItems;
    FIndex: SizeInt;
  protected
    function DoMoveNext: boolean; override;
    function DoGetCurrent: PT; override;
    function GetCurrent: PT; virtual;
  public
    constructor Create(AList: TList.PItems; ALow: SizeInt);
  end;

  TQueuePointersCollection<TPointersEnumerator, T, PT> = record
  private type
    TList = TCustomList<T>; // lazarus bug workaround
  private
    function List: TList.PItems; inline;
    function GetLow: SizeInt; inline;
    function GetCount: SizeInt; inline;
    function GetItem(AIndex: SizeInt): PT;
  public
    function GetEnumerator: TPointersEnumerator;
    function ToArray: TArray<PT>;
    property Count: SizeInt read GetCount;
    property Items[Index: SizeInt]: PT read GetItem; default;
  end;

  TQueue<T> = class(TCustomList<T>)
  private type
    TPointersEnumerator = class(TQueuePointersEnumerator<T, PT>);
    TPointersCollection = TQueuePointersCollection<TPointersEnumerator, T, PT>;
  public type
    PPointersCollection = ^TPointersCollection;
  private
    function GetPointers: PPointersCollection; inline;
  protected
    // bug #24287 - workaround for generics type name conflict (Identifier not found)
    // next bug workaround - for another error related to previous workaround
    // change order (function must be declared before TEnumerator declaration}
    function DoGetEnumerator: {Generics.Collections.}TEnumerator<T>; override;
  public
    type
      TEnumerator = class(TCustomListEnumerator<T>)
      public
        constructor Create(AQueue: TQueue<T>);
      end;

    function GetEnumerator: TEnumerator; reintroduce;
  private
    FLow: SizeInt;
  protected
    procedure SetCapacity(AValue: SizeInt); override;
    function DoRemove(AIndex: SizeInt; ACollectionNotification: TCollectionNotification): T; override;
    function GetCount: SizeInt; override;
  public
    constructor Create(ACollection: TEnumerable<T>); overload;
    destructor Destroy; override;
    procedure Enqueue(constref AValue: T);
    function Dequeue: T;
    function Extract: T;
    function Peek: T;
    procedure Clear;
    procedure TrimExcess;
    property Ptr: PPointersCollection read GetPointers;
  end;

  TStack<T> = class(TCustomListWithPointers<T>)
  protected
  // bug #24287 - workaround for generics type name conflict (Identifier not found)
  // next bug workaround - for another error related to previous workaround
  // change order (function must be declared before TEnumerator declaration}
    function DoGetEnumerator: {Generics.Collections.}TEnumerator<T>; override;
  public
    type
      TEnumerator = class(TCustomListEnumerator<T>);

    function GetEnumerator: TEnumerator; reintroduce;
  protected
    function DoRemove(AIndex: SizeInt; ACollectionNotification: TCollectionNotification): T; override;
    procedure SetCapacity(AValue: SizeInt); override;
  public
    constructor Create(ACollection: TEnumerable<T>); overload;
    destructor Destroy; override;
    procedure Clear;
    procedure Push(constref AValue: T);
    function Pop: T; inline;
    function Peek: T;
    function Extract: T; inline;
    procedure TrimExcess;
  end;

  TObjectList<T: class> = class(TList<T>)
  private
    FObjectsOwner: Boolean;
  protected
    procedure Notify(constref AValue: T; ACollectionNotification: TCollectionNotification); override;
  public
    constructor Create(AOwnsObjects: Boolean = True); overload;
    constructor Create(const AComparer: IComparer<T>; AOwnsObjects: Boolean = True); overload;
    constructor Create(ACollection: TEnumerable<T>; AOwnsObjects: Boolean = True); overload;
    property OwnsObjects: Boolean read FObjectsOwner write FObjectsOwner;
  end;

  TObjectQueue<T: class> = class(TQueue<T>)
  private
    FObjectsOwner: Boolean;
  protected
    procedure Notify(constref AValue: T; ACollectionNotification: TCollectionNotification); override;
  public
    constructor Create(AOwnsObjects: Boolean = True); overload;
    constructor Create(ACollection: TEnumerable<T>; AOwnsObjects: Boolean = True); overload;
    procedure Dequeue;
    property OwnsObjects: Boolean read FObjectsOwner write FObjectsOwner;
  end;

  TObjectStack<T: class> = class(TStack<T>)
  private
    FObjectsOwner: Boolean;
  protected
    procedure Notify(constref AValue: T; ACollectionNotification: TCollectionNotification); override;
  public
    constructor Create(AOwnsObjects: Boolean = True); overload;
    constructor Create(ACollection: TEnumerable<T>; AOwnsObjects: Boolean = True); overload;
    function Pop: T;
    property OwnsObjects: Boolean read FObjectsOwner write FObjectsOwner;
  end;

  PObject = ^TObject;

{$I inc\generics.dictionariesh.inc}

  { THashSet }

  THashSet<T> = class(TEnumerable<T>)
  protected
    FInternalDictionary : TOpenAddressingLP<T, TEmptyRecord>;
    function DoGetEnumerator: TEnumerator<T>; override;
    procedure InitializeSet; virtual;
  public type
    THashSetEnumerator = class(TEnumerator<T>)
    protected type
      TDictionaryEnumerator = TDictionary<T, TEmptyRecord>.TKeyEnumerator;
    protected var
      FEnumerator: TObject;
      function DoMoveNext: boolean; override;
      function DoGetCurrent: T; override;
      function GetCurrent: T; virtual;
    public
      constructor Create(ASet: THashSet<T>);
      destructor Destroy; override;
    end;
  private
    function GetCount: SizeInt; inline;
    function GetPointers: TDictionary<T, TEmptyRecord>.TKeyCollection.PPointersCollection; inline;
  public type
    //TEnumerator = TSetEnumerator;
    PT = ^T;

    function GetEnumerator: THashSetEnumerator; reintroduce; virtual;
  public
    constructor Create; virtual; overload;
    constructor Create(const AComparer: IEqualityComparer<T>); virtual; overload;
    constructor Create(ACollection: TEnumerable<T>); overload;
    destructor Destroy; override;
    function Add(constref AValue: T): Boolean; virtual;
    function Remove(constref AValue: T): Boolean; virtual;
    procedure Clear;
    function Contains(constref AValue: T): Boolean; inline;
    procedure UnionWith(AHashSet: THashSet<T>);
    procedure IntersectWith(AHashSet: THashSet<T>);
    procedure ExceptWith(AHashSet: THashSet<T>);
    procedure SymmetricExceptWith(AHashSet: THashSet<T>);
    property Count: SizeInt read GetCount;
    property Ptr: TDictionary<T, TEmptyRecord>.TKeyCollection.PPointersCollection read GetPointers;
  end;

  TPair<TKey, TValue, TInfo> = record
  public
    Key: TKey;
    Value: TValue;
  private
    Info: TInfo;
  end;

  TAVLTreeNode<TREE_CONSTRAINTS, TTree> = record
  private type
    TNodePair = TPair<TREE_CONSTRAINTS>;
  public type
    PNode = ^TAVLTreeNode<TREE_CONSTRAINTS, TTree>;
  public
    Parent, Left, Right: PNode;
    Balance: Integer;
    Data: TNodePair;
    function Successor: PNode;
    function Precessor: PNode;
    function TreeDepth: integer;
    procedure ConsistencyCheck(ATree: TObject); // workaround for internal error 2012101001 (no generic forward declarations)
    function GetCount: SizeInt;
    property Key: TKey read Data.Key write Data.Key;
    property Value: TValue read Data.Value write Data.Value;
    property Info: TInfo read Data.Info write Data.Info;
  end;

  TCustomTreeEnumerator<T, PNode, TTree> = class abstract(TEnumerator<T>)
  protected
    FCurrent: PNode;
    FTree: TTree;
    function DoGetCurrent: T; override;
    function GetCurrent: T; virtual; abstract;
  public
    constructor Create(ATree: TObject);
    function MoveNext: Boolean; virtual; abstract;
    property Current: T read GetCurrent;
  end;

  TCustomTree<TREE_CONSTRAINTS> = class
  end;

  TTreeEnumerable<TTreeEnumerator, TTreePointersEnumerator,
    T, PT, PNode, TTree> = class abstract(TEnumerable<T>)
  private type
    PPointersCollection = ^TPointersCollection;
    TPointersCollection = record
    private
      function Tree: TTree; inline;
      function GetCount: SizeInt; inline;
    public
      function GetEnumerator: TTreePointersEnumerator;
      function ToArray: TArray<PT>;
      property Count: SizeInt read GetCount;
    end;
  private
    FPointers: TPointersCollection;
    FTree: TTree;
    function GetCount: SizeInt;
    function GetPointers: PPointersCollection; inline;
  public
    constructor Create(ATree: TTree);
    function DoGetEnumerator: TTreeEnumerator; override;
    function ToArray: TArray<T>; override; final;
    property Count: SizeInt read GetCount;
    property Ptr: PPointersCollection read GetPointers;
  end;

  TAVLTreeEnumerator<T, PNode, TTree> = class(TCustomTreeEnumerator<T, PNode, TTree>)
  protected
    FLowToHigh: boolean;
    function DoMoveNext: Boolean; override;
  public
    constructor Create(ATree: TObject; ALowToHigh: boolean = true);
    property LowToHigh: boolean read FLowToHigh;
  end;

  TCustomAVLTreeMap<TREE_CONSTRAINTS> = class
  private type
    TTree = class(TCustomAVLTreeMap<TREE_CONSTRAINTS>);
  public type
    TNode = TAVLTreeNode<TREE_CONSTRAINTS, TTree>;
    PNode = ^TNode;
    TTreePair = TPair<TKey, TValue>;
  private type
    PPNode = ^PNode;
    // type exist only for generic constraint in TNodeCollection (non functional - PPNode has no sense)
    TPNodeEnumerator = class(TAVLTreeEnumerator<PPNode, PNode, TTree>);
  private var
    FComparer: IComparer<TKey>;
  protected
    FCount: SizeInt;
    FRoot: PNode;
    procedure NodeAdded(ANode: PNode); virtual;
    procedure DeletingNode(ANode: PNode; AOrigin: boolean); virtual;

    function AddNode: PNode; virtual; abstract;

    procedure DeleteNode(ANode: PNode; ADispose: boolean); overload; virtual; abstract;
    procedure DeleteNode(ANode: PNode); overload;

    function Compare(constref ALeft, ARight: TKey): Integer; inline;
    function FindPredecessor(ANode: PNode): PNode;


    procedure RotateRightRight(ANode: PNode); virtual;
    procedure RotateLeftLeft(ANode: PNode); virtual;
    procedure RotateRightLeft(ANode: PNode); virtual;
    procedure RotateLeftRight(ANode: PNode); virtual;

    // for reporting
    procedure WriteStr(AStream: TStream; const AText: string);
  public type
    TPairEnumerator = class(TAVLTreeEnumerator<TTreePair, PNode, TTree>)
    protected
      function GetCurrent: TTreePair; override;
    end;

    TNodeEnumerator = class(TAVLTreeEnumerator<PNode, PNode, TTree>)
    protected
      function GetCurrent: PNode; override;
    end;

    TKeyEnumerator = class(TAVLTreeEnumerator<TKey, PNode, TTree>)
    protected
      function GetCurrent: TKey; override;
    end;

    TValueEnumerator = class(TAVLTreeEnumerator<TValue, PNode, TTree>)
    protected
      function GetCurrent: TValue; override;
    end;

    TNodeCollection = class(TTreeEnumerable<TNodeEnumerator, TPNodeEnumerator, PNode, PPNode, PNode, TTree>)
    private
      property Ptr; // PPNode has no sense, so hide enumerator for PPNode
    end;

  private
    FNodes: TNodeCollection;
    function GetNodeCollection: TNodeCollection;
    procedure InternalDelete(ANode: PNode);
  public
    constructor Create; virtual;
    destructor Destroy; override;
    function Add(constref AKey: TKey; constref AValue: TValue): PNode;
    function Remove(constref AKey: TKey): boolean;
    procedure Delete(ANode: PNode; ADispose: boolean = true);

    function GetEnumerator: TPairEnumerator;
    property Nodes: TNodeCollection read GetNodeCollection;

    procedure Clear(ADisposeNodes: Boolean = true); virtual;

    function FindLowest: PNode; // O(log(n))
    function FindHighest: PNode; // O(log(n))

    property Count: SizeInt read FCount;
    property Root: PNode read FRoot;
    function Find(constref AKey: TKey): PNode; // O(log(n))

    procedure ConsistencyCheck; virtual;
    procedure WriteTreeNode(AStream: TStream; ANode: PNode);
    procedure WriteReportToStream(AStream: TStream);
    function NodeToReportStr(ANode: PNode): string; virtual;
    function ReportAsString: string;
  end;

  TAVLTreeMap<TKey, TValue> = class(TCustomAVLTreeMap<TKey, TValue, TEmptyRecord>)
  protected
    function AddNode: PNode; override;
    procedure DeleteNode(ANode: PNode; ADispose: boolean = true); override;
  end;

  TIndexedAVLTreeMap<TKey, TValue> = class(TCustomAVLTreeMap<TKey, TValue, SizeInt>)
  protected
    FLastNode: PNode;
    FLastIndex: SizeInt;

    procedure RotateRightRight(ANode: PNode); override;
    procedure RotateLeftLeft(ANode: PNode); override;
    procedure RotateRightLeft(ANode: PNode); override;
    procedure RotateLeftRight(ANode: PNode); override;

    procedure NodeAdded(ANode: PNode); override;
    procedure DeletingNode(ANode: PNode; AOrigin: boolean); override;

    function AddNode: PNode; override;
    procedure DeleteNode(ANode: PNode; ADispose: boolean = true); override;
  public
    function GetNodeAtIndex(AIndex: SizeInt): PNode;
    function NodeToIndex(ANode: PNode): SizeInt;

    procedure ConsistencyCheck; override;
    function NodeToReportStr(ANode: PNode): string; override;
  end;

  TAVLTree<T> = class(TAVLTreeMap<T, TEmptyRecord>)
  public
    function Add(constref AValue: T): PNode; reintroduce;
  end;

  TIndexedAVLTree<T> = class(TIndexedAVLTreeMap<T, TEmptyRecord>)
  public
    function Add(constref AValue: T): PNode; reintroduce;
  end;

  TSortedHashSet<T> = class(THashSet<T>)
  protected
    FInternalTree: TAVLTree<T>;
    function DoGetEnumerator: TEnumerator<T>; override;
    procedure InitializeSet; override;
  public type
    TSortedHashSetEnumerator = class(THashSetEnumerator)
    protected type
      TTreeEnumerator = TAVLTree<T>.TNodeEnumerator;
      function DoMoveNext: boolean; override;
      function DoGetCurrent: T; override;
      function GetCurrent: T; virtual;
    public
      constructor Create(ASet: TSortedHashSet<T>);
      destructor Destroy; override;
    end;
  public // type
    //TEnumerator = TSetEnumerator;

    function GetEnumerator: THashSetEnumerator; override;
  public
    function Add(constref AValue: T): Boolean; override;
    function Remove(constref AValue: T): Boolean; override;

    destructor Destroy; override;
  end;

function InCircularRange(ABottom, AItem, ATop: SizeInt): Boolean;

var
  EmptyRecord: TEmptyRecord;

implementation

function InCircularRange(ABottom, AItem, ATop: SizeInt): Boolean;
begin
  Result :=
       (ABottom < AItem) and (AItem <= ATop )
    or (ATop < ABottom) and (AItem > ABottom)
    or (ATop < ABottom ) and (AItem <= ATop );
end;

{ TCustomArrayHelper<T> }


class function TCustomArrayHelper<T>.BinarySearch(constref AValues: array of T; constref AItem: T;
  out AFoundIndex: SizeInt; const AComparer: IComparer<T>;
  AIndex, ACount: SizeInt): Boolean;
var
  LSearchResult: TBinarySearchResult;
begin
  Result := BinarySearch(AValues, AItem, LSearchResult, AComparer, Low(AValues), Length(AValues));
end;

class function TCustomArrayHelper<T>.BinarySearch(constref AValues: array of T; constref AItem: T;
  out AFoundIndex: SizeInt; const AComparer: IComparer<T>): Boolean;
begin
  Result := BinarySearch(AValues, AItem, AFoundIndex, AComparer, Low(AValues), Length(AValues));
end;

class function TCustomArrayHelper<T>.BinarySearch(constref AValues: array of T; constref AItem: T;
  out AFoundIndex: SizeInt): Boolean;
begin
  Result := BinarySearch(AValues, AItem, AFoundIndex, TComparerBugHack.Default, Low(AValues), Length(AValues));
end;

class function TCustomArrayHelper<T>.BinarySearch(constref AValues: array of T; constref AItem: T;
  out ASearchResult: TBinarySearchResult; const AComparer: IComparer<T>): Boolean;
begin
  Result := BinarySearch(AValues, AItem, ASearchResult, AComparer, Low(AValues), Length(AValues));
end;

class function TCustomArrayHelper<T>.BinarySearch(constref AValues: array of T; constref AItem: T;
  out ASearchResult: TBinarySearchResult): Boolean;
begin
  Result := BinarySearch(AValues, AItem, ASearchResult, TComparerBugHack.Default, Low(AValues), Length(AValues));
end;

class procedure TCustomArrayHelper<T>.Sort(var AValues: array of T);
begin
  QuickSort(AValues, Low(AValues), High(AValues), TComparerBugHack.Default);
end;

class procedure TCustomArrayHelper<T>.Sort(var AValues: array of T;
  const AComparer: IComparer<T>);
begin
  QuickSort(AValues, Low(AValues), High(AValues), AComparer);
end;

class procedure TCustomArrayHelper<T>.Sort(var AValues: array of T;
  const AComparer: IComparer<T>; AIndex, ACount: SizeInt);
begin
  if ACount <= 1 then
    Exit;
  QuickSort(AValues, AIndex, Pred(AIndex + ACount), AComparer);
end;

{ TArrayHelper<T> }

class procedure TArrayHelper<T>.QuickSort(var AValues: array of T; ALeft, ARight: SizeInt;
  const AComparer: IComparer<T>);
var
  I, J: SizeInt;
  P, Q: T;
begin
  if ((ARight - ALeft) <= 0) or (Length(AValues) = 0) then
    Exit;
  repeat
    I := ALeft;
    J := ARight;
    P := AValues[ALeft + (ARight - ALeft) shr 1];
    repeat
        while AComparer.Compare(AValues[I], P) < 0 do
          I += 1;
        while AComparer.Compare(AValues[J], P) > 0 do
          J -= 1;
      if I <= J then
      begin
        if I <> J then
        begin
          Q := AValues[I];
          AValues[I] := AValues[J];
          AValues[J] := Q;
        end;
        I += 1;
        J -= 1;
      end;
    until I > J;
    // sort the smaller range recursively
    // sort the bigger range via the loop
    // Reasons: memory usage is O(log(n)) instead of O(n) and loop is faster than recursion
    if J - ALeft < ARight - I then
    begin
      if ALeft < J then
        QuickSort(AValues, ALeft, J, AComparer);
      ALeft := I;
    end
    else
    begin
      if I < ARight then
        QuickSort(AValues, I, ARight, AComparer);
      ARight := J;
    end;
   until ALeft >= ARight;
end;

class function TArrayHelper<T>.BinarySearch(constref AValues: array of T; constref AItem: T;
  out ASearchResult: TBinarySearchResult; const AComparer: IComparer<T>;
  AIndex, ACount: SizeInt): Boolean;
var
  imin, imax, imid: Int32;
begin
  // continually narrow search until just one element remains
  imin := AIndex;
  imax := Pred(AIndex + ACount);

  // http://en.wikipedia.org/wiki/Binary_search_algorithm
  while (imin < imax) do
  begin
        imid := imin + ((imax - imin) shr 1);

        // code must guarantee the interval is reduced at each iteration
        // assert(imid < imax);
        // note: 0 <= imin < imax implies imid will always be less than imax

        ASearchResult.CompareResult := AComparer.Compare(AValues[imid], AItem);
        // reduce the search
        if (ASearchResult.CompareResult < 0) then
          imin := imid + 1
        else
        begin
          imax := imid;
          if ASearchResult.CompareResult = 0 then
          begin
            ASearchResult.FoundIndex := imid;
            ASearchResult.CandidateIndex := imid;
            Exit(True);
          end;
        end;
  end;
    // At exit of while:
    //   if A[] is empty, then imax < imin
    //   otherwise imax == imin

    // deferred test for equality

  if (imax = imin) then
  begin
    ASearchResult.CompareResult := AComparer.Compare(AValues[imin], AItem);
    ASearchResult.CandidateIndex := imin;
    if (ASearchResult.CompareResult = 0) then
    begin
      ASearchResult.FoundIndex := imin;
      Exit(True);
    end else
    begin
      ASearchResult.FoundIndex := -1;
      Exit(False);
    end;
  end
  else
  begin
    ASearchResult.CompareResult := 0;
    ASearchResult.FoundIndex := -1;
    ASearchResult.CandidateIndex := -1;
    Exit(False);
  end;
end;

{ TEnumerator<T> }

function TEnumerator<T>.MoveNext: boolean;
begin
  Exit(DoMoveNext);
end;

{ TEnumerable<T> }

function TEnumerable<T>.ToArrayImpl(ACount: SizeInt): TArray<T>;
var
  i: SizeInt;
  LEnumerator: TEnumerator<T>;
begin
  SetLength(Result, ACount);

  try
    LEnumerator := GetEnumerator;

    i := 0;
    while LEnumerator.MoveNext do
    begin
      Result[i] := LEnumerator.Current;
      Inc(i);
    end;
  finally
    LEnumerator.Free;
  end;
end;

function TEnumerable<T>.GetEnumerator: TEnumerator<T>;
begin
  Exit(DoGetEnumerator);
end;

function TEnumerable<T>.ToArray: TArray<T>;
var
  LEnumerator: TEnumerator<T>;
  LBuffer: TList<T>;
begin
  LBuffer := TList<T>.Create;
  try
    LEnumerator := GetEnumerator;

    while LEnumerator.MoveNext do
      LBuffer.Add(LEnumerator.Current);

    Result := LBuffer.ToArray;
  finally
    LBuffer.Free;
    LEnumerator.Free;
  end;
end;

{ TCustomList<T> }

function TCustomList<T>.PrepareAddingItem: SizeInt;
begin
  Result := Length(FItems.FItems);

  if (FItems.FLength < 4) and (Result < 4) then
    SetLength(FItems.FItems, 4)
  else if FItems.FLength = High(FItems.FLength) then
    OutOfMemoryError
  else if FItems.FLength = Result then
    SetLength(FItems.FItems, CUSTOM_LIST_CAPACITY_INC);

  Result := FItems.FLength;
  Inc(FItems.FLength);
end;

function TCustomList<T>.PrepareAddingRange(ACount: SizeInt): SizeInt;
begin
  if ACount < 0 then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);
  if ACount = 0 then
    Exit(FItems.FLength - 1);

  if (FItems.FLength = 0) and (Length(FItems.FItems) = 0) then
    SetLength(FItems.FItems, 4)
  else if FItems.FLength = High(FItems.FLength) then
    OutOfMemoryError;

  Result := Length(FItems.FItems);
  while Pred(FItems.FLength + ACount) >= Result do
  begin
    SetLength(FItems.FItems, CUSTOM_LIST_CAPACITY_INC);
    Result := Length(FItems.FItems);
  end;

  Result := FItems.FLength;
  Inc(FItems.FLength, ACount);
end;

function TCustomList<T>.ToArray: TArray<T>;
begin
  Result := ToArrayImpl(Count);
end;

function TCustomList<T>.GetCount: SizeInt;
begin
  Result := FItems.FLength;
end;

procedure TCustomList<T>.Notify(constref AValue: T; ACollectionNotification: TCollectionNotification);
begin
  if Assigned(FOnNotify) then
    FOnNotify(Self, AValue, ACollectionNotification);
end;

function TCustomList<T>.DoRemove(AIndex: SizeInt; ACollectionNotification: TCollectionNotification): T;
begin
  if (AIndex < 0) or (AIndex >= FItems.FLength) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  Result := FItems.FItems[AIndex];
  Dec(FItems.FLength);

  FItems.FItems[AIndex] := Default(T);
  if AIndex <> FItems.FLength then
  begin
    System.Move(FItems.FItems[AIndex + 1], FItems.FItems[AIndex], (FItems.FLength - AIndex) * SizeOf(T));
    FillChar(FItems.FItems[FItems.FLength], SizeOf(T), 0);
  end;

  Notify(Result, ACollectionNotification);
end;

function TCustomList<T>.GetCapacity: SizeInt;
begin
  Result := Length(FItems.FItems);
end;

{ TCustomListEnumerator<T> }

function TCustomListEnumerator<T>.DoMoveNext: boolean;
begin
  Inc(FIndex);
  Result := (FList.FItems.FLength <> 0) and (FIndex < FList.FItems.FLength)
end;

function TCustomListEnumerator<T>.DoGetCurrent: T;
begin
  Result := GetCurrent;
end;

function TCustomListEnumerator<T>.GetCurrent: T;
begin
  Result := FList.FItems.FItems[FIndex];
end;

constructor TCustomListEnumerator<T>.Create(AList: TCustomList<T>);
begin
  inherited Create;
  FIndex := -1;
  FList := AList;
end;

{ TCustomListPointersEnumerator<T, PT> }

function TCustomListPointersEnumerator<T, PT>.DoMoveNext: boolean;
begin
  Inc(FIndex);
  Result := (FList.FLength <> 0) and (FIndex < FList.FLength)
end;

function TCustomListPointersEnumerator<T, PT>.DoGetCurrent: PT;
begin
  Result := GetCurrent;
end;

function TCustomListPointersEnumerator<T, PT>.GetCurrent: PT;
begin
  Result := @FList.FItems[FIndex];
end;

constructor TCustomListPointersEnumerator<T, PT>.Create(AList: TCustomList<T>.PItems);
begin
  inherited Create;
  FIndex := -1;
  FList := AList;
end;

{ TCustomListPointersCollection<TPointersEnumerator, T, PT> }

function TCustomListPointersCollection<TPointersEnumerator, T, PT>.List: TCustomList<T>.PItems;
begin
  Result := @(TCustomList<T>.TItems(Pointer(@Self)^));
end;

function TCustomListPointersCollection<TPointersEnumerator, T, PT>.GetCount: SizeInt;
begin
  Result := List.FLength;
end;

function TCustomListPointersCollection<TPointersEnumerator, T, PT>.GetItem(AIndex: SizeInt): PT;
begin
  Result := @List.FItems[AIndex];
end;

function TCustomListPointersCollection<TPointersEnumerator, T, PT>.{Do}GetEnumerator: TPointersEnumerator;
begin
  Result := TPointersEnumerator(TPointersEnumerator.NewInstance);
  TCustomListPointersEnumerator<T, PT>(Result).Create(List);
end;

function TCustomListPointersCollection<TPointersEnumerator, T, PT>.ToArray: TArray<PT>;
{begin
  Result := ToArrayImpl(FList.Count);
end;}
var
  i: SizeInt;
  LEnumerator: TPointersEnumerator;
begin
  SetLength(Result, Count);

  try
    LEnumerator := GetEnumerator;

    i := 0;
    while LEnumerator.MoveNext do
    begin
      Result[i] := LEnumerator.Current;
      Inc(i);
    end;
  finally
    LEnumerator.Free;
  end;
end;

{ TCustomListWithPointers<T> }

function TCustomListWithPointers<T>.GetPointers: PPointersCollection;
begin
  Result := PPointersCollection(@FItems);
end;

{ TList<T> }

procedure TList<T>.InitializeList;
begin
end;

constructor TList<T>.Create;
begin
  InitializeList;
  FComparer := TComparer<T>.Default;
end;

constructor TList<T>.Create(const AComparer: IComparer<T>);
begin
  InitializeList;
  FComparer := AComparer;
end;

constructor TList<T>.Create(ACollection: TEnumerable<T>);
var
  LItem: T;
begin
  Create;
  for LItem in ACollection do
    Add(LItem);
end;

destructor TList<T>.Destroy;
begin
  SetCapacity(0);
end;

procedure TList<T>.SetCapacity(AValue: SizeInt);
begin
  if AValue < Count then
    Count := AValue;

  SetLength(FItems.FItems, AValue);
end;

procedure TList<T>.SetCount(AValue: SizeInt);
begin
  if AValue < 0 then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  if AValue > Capacity then
    Capacity := AValue;
  if AValue < Count then
    DeleteRange(AValue, Count - AValue);

  FItems.FLength := AValue;
end;

function TList<T>.GetItem(AIndex: SizeInt): T;
begin
  if (AIndex < 0) or (AIndex >= Count) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  Result := FItems.FItems[AIndex];
end;

procedure TList<T>.SetItem(AIndex: SizeInt; const AValue: T);
begin
  if (AIndex < 0) or (AIndex >= Count) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);   
  Notify(FItems.FItems[AIndex], cnRemoved);
  FItems.FItems[AIndex] := AValue;
  Notify(AValue, cnAdded);
end;

function TList<T>.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(Self);
end;

function TList<T>.DoGetEnumerator: {Generics.Collections.}TEnumerator<T>;
begin
  Result := GetEnumerator;
end;

function TList<T>.Add(constref AValue: T): SizeInt;
begin
  Result := PrepareAddingItem;
  FItems.FItems[Result] := AValue;
  Notify(AValue, cnAdded);
end;

procedure TList<T>.AddRange(constref AValues: array of T);
begin
  InsertRange(Count, AValues);
end;

procedure TList<T>.AddRange(const AEnumerable: IEnumerable<T>);
var
  LValue: T;
begin
  for LValue in AEnumerable do
    Add(LValue);
end;

procedure TList<T>.AddRange(AEnumerable: TEnumerable<T>);
var
  LValue: T;
begin
  for LValue in AEnumerable do
    Add(LValue);
end;

procedure TList<T>.InternalInsert(AIndex: SizeInt; constref AValue: T);
begin
  if AIndex <> PrepareAddingItem then
  begin
    System.Move(FItems.FItems[AIndex], FItems.FItems[AIndex + 1], ((Count - AIndex) - 1) * SizeOf(T));
    FillChar(FItems.FItems[AIndex], SizeOf(T), 0);
  end;

  FItems.FItems[AIndex] := AValue;
  Notify(AValue, cnAdded);
end;

procedure TList<T>.Insert(AIndex: SizeInt; constref AValue: T);
begin
  if (AIndex < 0) or (AIndex > Count) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  InternalInsert(AIndex, AValue);
end;

procedure TList<T>.InsertRange(AIndex: SizeInt; constref AValues: array of T);
var
  i: SizeInt;
  LLength: SizeInt;
  LValue: ^T;
begin
  if (AIndex < 0) or (AIndex > Count) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  LLength := Length(AValues);
  if LLength = 0 then
    Exit;

  if AIndex <> PrepareAddingRange(LLength) then
  begin
    System.Move(FItems.FItems[AIndex], FItems.FItems[AIndex + LLength], ((Count - AIndex) - LLength) * SizeOf(T));
    FillChar(FItems.FItems[AIndex], SizeOf(T) * LLength, 0);
  end;

  LValue := @AValues[0];
  for i := AIndex to Pred(AIndex + LLength) do
  begin
    FItems.FItems[i] := LValue^;
    Notify(LValue^, cnAdded);
    Inc(LValue);
  end;
end;

procedure TList<T>.InsertRange(AIndex: SizeInt; const AEnumerable: IEnumerable<T>);
var
  LValue: T;
  i: SizeInt;
begin
  if (AIndex < 0) or (AIndex > Count) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  i := 0;
  for LValue in AEnumerable do
  begin
    InternalInsert(Aindex + i, LValue);
    Inc(i);
  end;
end;

procedure TList<T>.InsertRange(AIndex: SizeInt; const AEnumerable: TEnumerable<T>);
var
  LValue: T;
  i:  SizeInt;
begin
  if (AIndex < 0) or (AIndex > Count) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  i := 0;
  for LValue in AEnumerable do
  begin
    InternalInsert(Aindex + i, LValue);
    Inc(i);
  end;
end;

function TList<T>.Remove(constref AValue: T): SizeInt;
begin
  Result := IndexOf(AValue);
  if Result >= 0 then
    DoRemove(Result, cnRemoved);
end;

procedure TList<T>.Delete(AIndex: SizeInt);
begin
  DoRemove(AIndex, cnRemoved);
end;

procedure TList<T>.DeleteRange(AIndex, ACount: SizeInt);
var
  LDeleted: array of T;
  i: SizeInt;
  LMoveDelta: SizeInt;
begin
  if ACount = 0 then
    Exit;

  if (ACount < 0) or (AIndex < 0) or (AIndex + ACount > Count) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  SetLength(LDeleted, Count);
  System.Move(FItems.FItems[AIndex], LDeleted[0], ACount * SizeOf(T));

  LMoveDelta := Count - (AIndex + ACount);

  if LMoveDelta = 0 then
    FillChar(FItems.FItems[AIndex], ACount * SizeOf(T), #0)
  else
  begin
    System.Move(FItems.FItems[AIndex + ACount], FItems.FItems[AIndex], LMoveDelta * SizeOf(T));
    FillChar(FItems.FItems[Count - ACount], ACount * SizeOf(T), #0);
  end;

  FItems.FLength -= ACount;

  for i := 0 to High(LDeleted) do
    Notify(LDeleted[i], cnRemoved);
end;

function TList<T>.ExtractIndex(const AIndex: SizeInt): T;
begin
  Result := DoRemove(AIndex, cnExtracted);
end;

function TList<T>.Extract(constref AValue: T): T;
var
  LIndex: SizeInt;
begin
  LIndex := IndexOf(AValue);
  if LIndex < 0 then
    Exit(Default(T));

  Result := DoRemove(LIndex, cnExtracted);
end;

procedure TList<T>.Exchange(AIndex1, AIndex2: SizeInt);
var
  LTemp: T;
begin
  LTemp := FItems.FItems[AIndex1];
  FItems.FItems[AIndex1] := FItems.FItems[AIndex2];
  FItems.FItems[AIndex2] := LTemp;
end;

procedure TList<T>.Move(AIndex, ANewIndex: SizeInt);
var
  LTemp: T;
begin
  if ANewIndex = AIndex then
    Exit;

  if (ANewIndex < 0) or (ANewIndex >= Count) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  LTemp := FItems.FItems[AIndex];
  FItems.FItems[AIndex] := Default(T);

  if AIndex < ANewIndex then
    System.Move(FItems.FItems[Succ(AIndex)], FItems.FItems[AIndex], (ANewIndex - AIndex) * SizeOf(T))
  else
    System.Move(FItems.FItems[ANewIndex], FItems.FItems[Succ(ANewIndex)], (AIndex - ANewIndex) * SizeOf(T));

  FillChar(FItems.FItems[ANewIndex], SizeOf(T), #0);
  FItems.FItems[ANewIndex] := LTemp;
end;

function TList<T>.First: T;
begin
  Result := Items[0];
end;

function TList<T>.Last: T;
begin
  Result := Items[Pred(Count)];
end;

procedure TList<T>.Clear;
begin
  SetCount(0);
  SetCapacity(0);
end;

procedure TList<T>.TrimExcess;
begin
  SetCapacity(Count);
end;

function TList<T>.Contains(constref AValue: T): Boolean;
begin
  Result := IndexOf(AValue) >= 0;
end;

function TList<T>.IndexOf(constref AValue: T): SizeInt;
var
  i: SizeInt;
begin
  for i := 0 to Count - 1 do
    if FComparer.Compare(AValue, FItems.FItems[i]) = 0 then
      Exit(i);
  Result := -1;
end;

function TList<T>.LastIndexOf(constref AValue: T): SizeInt;
var
  i: SizeInt;
begin
  for i := Count - 1 downto 0 do
    if FComparer.Compare(AValue, FItems.FItems[i]) = 0 then
      Exit(i);
  Result := -1;
end;

procedure TList<T>.Reverse;
var
  a, b: SizeInt;
  LTemp: T;
begin
  a := 0;
  b := Count - 1;
  while a < b do
  begin
    LTemp := FItems.FItems[a];
    FItems.FItems[a] := FItems.FItems[b];
    FItems.FItems[b] := LTemp;
    Inc(a);
    Dec(b);
  end;
end;

procedure TList<T>.Sort;
begin
  TArrayHelperBugHack.Sort(FItems.FItems, FComparer, 0, Count);
end;

procedure TList<T>.Sort(const AComparer: IComparer<T>);
begin
  TArrayHelperBugHack.Sort(FItems.FItems, AComparer, 0, Count);
end;

function TList<T>.BinarySearch(constref AItem: T; out AIndex: SizeInt): Boolean;
begin
  Result := TArrayHelperBugHack.BinarySearch(FItems.FItems, AItem, AIndex, FComparer, 0, Count);
end;

function TList<T>.BinarySearch(constref AItem: T; out AIndex: SizeInt; const AComparer: IComparer<T>): Boolean;
begin
  Result := TArrayHelperBugHack.BinarySearch(FItems.FItems, AItem, AIndex, AComparer, 0, Count);
end;

{ TSortedList<T> }

procedure TSortedList<T>.InitializeList;
begin
  FSortStyle := cssAuto;
end;

function TSortedList<T>.Add(constref AValue: T): SizeInt;
var
  LSearchResult: TBinarySearchResult;
begin
  if SortStyle <> cssAuto then
    Exit(inherited Add(AValue));
  if TArrayHelperBugHack.BinarySearch(FItems.FItems, AValue, LSearchResult, FComparer, 0, Count) then
  case FDuplicates of
    dupAccept: Result := LSearchResult.FoundIndex;
    dupIgnore: Exit(LSearchResult.FoundIndex);
    dupError: raise EListError.Create(SCollectionDuplicate);
  end
  else
  begin
    if LSearchResult.CandidateIndex = -1 then
      Result := 0
    else
      if LSearchResult.CompareResult > 0 then
        Result := LSearchResult.CandidateIndex
      else
        Result := LSearchResult.CandidateIndex + 1;
  end;

  InternalInsert(Result, AValue);
end;

procedure TSortedList<T>.Insert(AIndex: SizeInt; constref AValue: T);
begin
  if FSortStyle = cssAuto then
    raise EListError.Create(SSortedListError)
  else
    inherited;
end;

procedure TSortedList<T>.Exchange(AIndex1, AIndex2: SizeInt);
begin
  if FSortStyle = cssAuto then
    raise EListError.Create(SSortedListError)
  else
    inherited;
end;

procedure TSortedList<T>.Move(AIndex, ANewIndex: SizeInt);
begin
  if FSortStyle = cssAuto then
    raise EListError.Create(SSortedListError)
  else
    inherited;
end;

procedure TSortedList<T>.AddRange(constref AValues: array of T);
var
  i: T;
begin
  for i in AValues do
    Add(i);
end;

procedure TSortedList<T>.InsertRange(AIndex: SizeInt; constref AValues: array of T);
var
  LValue: T;
  i:  SizeInt;
begin
  if (AIndex < 0) or (AIndex > Count) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  i := 0;
  for LValue in AValues do
  begin
    InternalInsert(AIndex + i, LValue);
    Inc(i);
  end;
end;

function TSortedList<T>.GetSorted: boolean;
begin
  Result := FSortStyle in [cssAuto, cssUser];
end;

procedure TSortedList<T>.SetSorted(AValue: boolean);
begin
  if AValue then
    SortStyle := cssAuto
  else
    SortStyle := cssNone;
end;

procedure TSortedList<T>.SetSortStyle(AValue: TCollectionSortStyle);
begin
  if FSortStyle = AValue then
    Exit;
  if AValue = cssAuto then
    Sort;
  FSortStyle := AValue;
end;

function TSortedList<T>.ConsistencyCheck(ARaiseException: boolean = true): boolean;
var
  i: Integer;
  LCompare: SizeInt;
begin
  if Sorted then
  for i := 0 to Count-2 do
  begin
    LCompare := FComparer.Compare(FItems.FItems[i], FItems.FItems[i+1]);
    if LCompare = 0 then
    begin
      if Duplicates <> dupAccept then
        if ARaiseException then
          raise EListError.Create(SCollectionDuplicate)
        else
          Exit(False)
    end
    else
      if LCompare > 0 then
        if ARaiseException then
          raise EListError.Create(SCollectionInconsistency)
        else
          Exit(False)
  end;
  Result := True;
end;

{ TThreadList<T> }

constructor TThreadList<T>.Create;
begin
  inherited Create;
  FDuplicates:=dupIgnore;
{$ifdef FPC_HAS_FEATURE_THREADING}
  InitCriticalSection(FLock);
{$endif}
  FList := TList<T>.Create;
end;

destructor TThreadList<T>.Destroy;
begin
  LockList;
  try
    FList.Free;
    inherited Destroy;
  finally
    UnlockList;
{$ifdef FPC_HAS_FEATURE_THREADING}
    DoneCriticalSection(FLock);
{$endif}
  end;
end;

procedure TThreadList<T>.Add(constref AValue: T);
begin
  LockList;
  try
    if (Duplicates = dupAccept) or (FList.IndexOf(AValue) = -1) then
      FList.Add(AValue)
    else if Duplicates = dupError then
      raise EArgumentException.CreateRes(@SDuplicatesNotAllowed);
  finally
    UnlockList;
  end;
end;

procedure TThreadList<T>.Remove(constref AValue: T);
begin
  LockList;
  try
    FList.Remove(AValue);
  finally
    UnlockList;
  end;
end;

procedure TThreadList<T>.Clear;
begin
  LockList;
  try
    FList.Clear;
  finally
    UnlockList;
  end;
end;

function TThreadList<T>.LockList: TList<T>;
begin
  Result:=FList;
{$ifdef FPC_HAS_FEATURE_THREADING}
  System.EnterCriticalSection(FLock);
{$endif}
end;

procedure TThreadList<T>.UnlockList;
begin
{$ifdef FPC_HAS_FEATURE_THREADING}
  System.LeaveCriticalSection(FLock);
{$endif}
end;

{ TQueuePointersEnumerator<T, PT> }

function TQueuePointersEnumerator<T, PT>.DoMoveNext: boolean;
begin
  Inc(FIndex);
  Result := (FList.FLength <> 0) and (FIndex < FList.FLength)
end;

function TQueuePointersEnumerator<T, PT>.DoGetCurrent: PT;
begin
  Result := GetCurrent;
end;

function TQueuePointersEnumerator<T, PT>.GetCurrent: PT;
begin
  Result := @FList.FItems[FIndex];
end;

constructor TQueuePointersEnumerator<T, PT>.Create(AList: TList.PItems; ALow: SizeInt);
begin
  inherited Create;
  FIndex := Pred(ALow);
  FList := AList;
end;

{ TQueuePointersCollection<TPointersEnumerator, T, PT> }

function TQueuePointersCollection<TPointersEnumerator, T, PT>.List: TList.PItems;
begin
  Result := @(TCustomList<T>.TItems(Pointer(@Self)^));
end;

function TQueuePointersCollection<TPointersEnumerator, T, PT>.GetLow: SizeInt;
begin
  Result := PSizeInt(PByte(@((@Self)^))+SizeOf(TCustomList<T>.TItems))^;
end;

function TQueuePointersCollection<TPointersEnumerator, T, PT>.GetCount: SizeInt;
begin
  Result := List.FLength;
end;

function TQueuePointersCollection<TPointersEnumerator, T, PT>.GetItem(AIndex: SizeInt): PT;
begin
  Result := @List.FItems[AIndex + GetLow];
end;

function TQueuePointersCollection<TPointersEnumerator, T, PT>.GetEnumerator: TPointersEnumerator;
begin
  Result := TPointersEnumerator(TPointersEnumerator.NewInstance);
  TPointersEnumerator(Result).Create(List, GetLow);
end;

function TQueuePointersCollection<TPointersEnumerator, T, PT>.ToArray: TArray<PT>;
{begin
  Result := ToArrayImpl(FList.Count);
end;}
var
  i: SizeInt;
  LEnumerator: TPointersEnumerator;
begin
  SetLength(Result, Count);

  try
    LEnumerator := GetEnumerator;

    i := 0;
    while LEnumerator.MoveNext do
    begin
      Result[i] := LEnumerator.Current;
      Inc(i);
    end;
  finally
    LEnumerator.Free;
  end;
end;

{ TQueue<T>.TEnumerator }

constructor TQueue<T>.TEnumerator.Create(AQueue: TQueue<T>);
begin
  inherited Create(AQueue);

  FIndex := Pred(AQueue.FLow);
end;

{ TQueue<T> }

function TQueue<T>.GetPointers: PPointersCollection;
begin
  Result := PPointersCollection(@FItems);
end;

function TQueue<T>.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(Self);
end;

function TQueue<T>.DoGetEnumerator: {Generics.Collections.}TEnumerator<T>;
begin
  Result := GetEnumerator;
end;

function TQueue<T>.DoRemove(AIndex: SizeInt; ACollectionNotification: TCollectionNotification): T;
begin
  Result := FItems.FItems[AIndex];
  FItems.FItems[AIndex] := Default(T);
  Notify(Result, ACollectionNotification);
  FLow += 1;
  if FLow = FItems.FLength then
  begin
    FLow := 0;
    FItems.FLength := 0;
  end;
end;

procedure TQueue<T>.SetCapacity(AValue: SizeInt);
begin
  if AValue < Count then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  if AValue = FItems.FLength then
    Exit;

  if (Count > 0) and (FLow > 0) then
  begin
    Move(FItems.FItems[FLow], FItems.FItems[0], Count * SizeOf(T));
    FillChar(FItems.FItems[Count], (FItems.FLength - Count) * SizeOf(T), #0);
  end;

  SetLength(FItems.FItems, AValue);
  FItems.FLength := Count;
  FLow := 0;
end;

function TQueue<T>.GetCount: SizeInt;
begin
  Result := FItems.FLength - FLow;
end;

constructor TQueue<T>.Create(ACollection: TEnumerable<T>);
var
  LItem: T;
begin
  for LItem in ACollection do
    Enqueue(LItem);
end;

destructor TQueue<T>.Destroy;
begin
  Clear;
end;

procedure TQueue<T>.Enqueue(constref AValue: T);
var
  LIndex: SizeInt;
begin
  LIndex := PrepareAddingItem;
  FItems.FItems[LIndex] := AValue;
  Notify(AValue, cnAdded);
end;

function TQueue<T>.Dequeue: T;
begin
  Result := DoRemove(FLow, cnRemoved);
end;

function TQueue<T>.Extract: T;
begin
  Result := DoRemove(FLow, cnExtracted);
end;

function TQueue<T>.Peek: T;
begin
  if (Count = 0) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  Result := FItems.FItems[FLow];
end;

procedure TQueue<T>.Clear;
begin
  while Count <> 0 do
    Dequeue;
  FLow := 0;
  FItems.FLength := 0;
end;

procedure TQueue<T>.TrimExcess;
begin
  SetCapacity(Count);
end;

{ TStack<T> }

function TStack<T>.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(Self);
end;

function TStack<T>.DoGetEnumerator: {Generics.Collections.}TEnumerator<T>;
begin
  Result := GetEnumerator;
end;

constructor TStack<T>.Create(ACollection: TEnumerable<T>);
var
  LItem: T;
begin
  for LItem in ACollection do
    Push(LItem);
end;

function TStack<T>.DoRemove(AIndex: SizeInt; ACollectionNotification: TCollectionNotification): T;
begin
  if AIndex < 0 then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  Result := FItems.FItems[AIndex];
  FItems.FItems[AIndex] := Default(T);
  FItems.FLength -= 1;
  Notify(Result, ACollectionNotification);
end;

destructor TStack<T>.Destroy;
begin
  Clear;
end;

procedure TStack<T>.Clear;
begin
  while Count <> 0 do
    Pop;
end;

procedure TStack<T>.SetCapacity(AValue: SizeInt);
begin
  if AValue < Count then
    AValue := Count;

  SetLength(FItems.FItems, AValue);
end;

procedure TStack<T>.Push(constref AValue: T);
var
  LIndex: SizeInt;
begin
  LIndex := PrepareAddingItem;
  FItems.FItems[LIndex] := AValue;
  Notify(AValue, cnAdded);
end;

function TStack<T>.Pop: T;
begin
  Result := DoRemove(FItems.FLength - 1, cnRemoved);
end;

function TStack<T>.Peek: T;
begin
  if (Count = 0) then
    raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);

  Result := FItems.FItems[FItems.FLength - 1];
end;

function TStack<T>.Extract: T;
begin
  Result := DoRemove(FItems.FLength - 1, cnExtracted);
end;

procedure TStack<T>.TrimExcess;
begin
  SetCapacity(Count);
end;

{ TObjectList<T> }

procedure TObjectList<T>.Notify(constref AValue: T; ACollectionNotification: TCollectionNotification);
begin
  inherited Notify(AValue, ACollectionNotification);

  if FObjectsOwner and (ACollectionNotification = cnRemoved) then
    TObject(AValue).Free;
end;

constructor TObjectList<T>.Create(AOwnsObjects: Boolean);
begin
  inherited Create;

  FObjectsOwner := AOwnsObjects;
end;

constructor TObjectList<T>.Create(const AComparer: IComparer<T>; AOwnsObjects: Boolean);
begin
  inherited Create(AComparer);

  FObjectsOwner := AOwnsObjects;
end;

constructor TObjectList<T>.Create(ACollection: TEnumerable<T>; AOwnsObjects: Boolean);
begin
  inherited Create(ACollection);

  FObjectsOwner := AOwnsObjects;
end;

{ TObjectQueue<T> }

procedure TObjectQueue<T>.Notify(constref AValue: T; ACollectionNotification: TCollectionNotification);
begin
  inherited Notify(AValue, ACollectionNotification);
  if FObjectsOwner and (ACollectionNotification = cnRemoved) then
    TObject(AValue).Free;
end;

constructor TObjectQueue<T>.Create(AOwnsObjects: Boolean);
begin
  inherited Create;

  FObjectsOwner := AOwnsObjects;
end;

constructor TObjectQueue<T>.Create(ACollection: TEnumerable<T>; AOwnsObjects: Boolean);
begin
  inherited Create(ACollection);

  FObjectsOwner := AOwnsObjects;
end;

procedure TObjectQueue<T>.Dequeue;
begin
  inherited Dequeue;
end;

{ TObjectStack<T> }

procedure TObjectStack<T>.Notify(constref AValue: T; ACollectionNotification: TCollectionNotification);
begin
  inherited Notify(AValue, ACollectionNotification);
  if FObjectsOwner and (ACollectionNotification = cnRemoved) then
    TObject(AValue).Free;
end;

constructor TObjectStack<T>.Create(AOwnsObjects: Boolean);
begin
  inherited Create;

  FObjectsOwner := AOwnsObjects;
end;

constructor TObjectStack<T>.Create(ACollection: TEnumerable<T>; AOwnsObjects: Boolean);
begin
  inherited Create(ACollection);

  FObjectsOwner := AOwnsObjects;
end;

function TObjectStack<T>.Pop: T;
begin
  Result := inherited Pop;
end;

{$I inc\generics.dictionaries.inc}

{ THashSet<T>.THashSetEnumerator }

function THashSet<T>.THashSetEnumerator.DoMoveNext: boolean;
begin
  Result := TDictionaryEnumerator(FEnumerator).DoMoveNext;
end;

function THashSet<T>.THashSetEnumerator.DoGetCurrent: T;
begin
  Result := TDictionaryEnumerator(FEnumerator).DoGetCurrent;
end;

function THashSet<T>.THashSetEnumerator.GetCurrent: T;
begin
  Result := TDictionaryEnumerator(FEnumerator).GetCurrent;
end;

constructor THashSet<T>.THashSetEnumerator.Create(ASet: THashSet<T>);
begin
  TDictionaryEnumerator(FEnumerator) := ASet.FInternalDictionary.Keys.DoGetEnumerator;
end;

destructor THashSet<T>.THashSetEnumerator.Destroy;
begin
  FEnumerator.Free;
end;

{ THashSet<T>.TEnumerator }

function THashSet<T>.DoGetEnumerator: Generics.Collections.TEnumerator<T>;
begin
  Result := GetEnumerator;
end;

procedure THashSet<T>.InitializeSet;
begin
end;

function THashSet<T>.GetCount: SizeInt;
begin
  Result := FInternalDictionary.Count;
end;

function THashSet<T>.GetPointers: TDictionary<T, TEmptyRecord>.TKeyCollection.PPointersCollection;
begin
  Result := FInternalDictionary.Keys.Ptr;
end;

function THashSet<T>.GetEnumerator: THashSetEnumerator;
begin
  Result := THashSetEnumerator.Create(Self);
end;

constructor THashSet<T>.Create;
begin
  InitializeSet;
  FInternalDictionary := TOpenAddressingLP<T, TEmptyRecord>.Create;
end;

constructor THashSet<T>.Create(const AComparer: IEqualityComparer<T>);
begin
  InitializeSet;
  FInternalDictionary := TOpenAddressingLP<T, TEmptyRecord>.Create(AComparer);
end;

constructor THashSet<T>.Create(ACollection: TEnumerable<T>);
var
  i: T;
begin
  Create;
  for i in ACollection do
    Add(i);
end;

destructor THashSet<T>.Destroy;
begin
  FInternalDictionary.Free;
end;

function THashSet<T>.Add(constref AValue: T): Boolean;
begin
  Result := not FInternalDictionary.ContainsKey(AValue);
  if Result then
    FInternalDictionary.Add(AValue, EmptyRecord);
end;

function THashSet<T>.Remove(constref AValue: T): Boolean;
var
  LIndex: SizeInt;
begin
  LIndex := FInternalDictionary.FindBucketIndex(AValue);
  Result := LIndex >= 0;
  if Result then
    FInternalDictionary.DoRemove(LIndex, cnRemoved);
end;

procedure THashSet<T>.Clear;
begin
  FInternalDictionary.Clear;
end;

function THashSet<T>.Contains(constref AValue: T): Boolean;
begin
  Result := FInternalDictionary.ContainsKey(AValue);
end;

procedure THashSet<T>.UnionWith(AHashSet: THashSet<T>);
var
  i: PT;
begin
  for i in AHashSet.Ptr^ do
    Add(i^);
end;

procedure THashSet<T>.IntersectWith(AHashSet: THashSet<T>);
var
  LList: TList<PT>;
  i: PT;
begin
  LList := TList<PT>.Create;

  for i in Ptr^ do
    if not AHashSet.Contains(i^) then
      LList.Add(i);

  for i in LList do
    Remove(i^);

  LList.Free;
end;

procedure THashSet<T>.ExceptWith(AHashSet: THashSet<T>);
var
  i: PT;
begin
  for i in AHashSet.Ptr^ do
    FInternalDictionary.Remove(i^);
end;

procedure THashSet<T>.SymmetricExceptWith(AHashSet: THashSet<T>);
var
  LList: TList<PT>;
  i: PT;
begin
  LList := TList<PT>.Create;

  for i in AHashSet.Ptr^ do
    if Contains(i^) then
      LList.Add(i)
    else
      Add(i^);

  for i in LList do
    Remove(i^);

  LList.Free;
end;

{ TAVLTreeNode<TREE_CONSTRAINTS, TTree> }

function TAVLTreeNode<TREE_CONSTRAINTS, TTree>.Successor: PNode;
begin
  Result:=Right;
  if Result<>nil then begin
    while (Result.Left<>nil) do Result:=Result.Left;
  end else begin
    Result:=@Self;
    while (Result.Parent<>nil) and (Result.Parent.Right=Result) do
      Result:=Result.Parent;
    Result:=Result.Parent;
  end;
end;

function TAVLTreeNode<TREE_CONSTRAINTS, TTree>.Precessor: PNode;
begin
  Result:=Left;
  if Result<>nil then begin
    while (Result.Right<>nil) do Result:=Result.Right;
  end else begin
    Result:=@Self;
    while (Result.Parent<>nil) and (Result.Parent.Left=Result) do
      Result:=Result.Parent;
    Result:=Result.Parent;
  end;
end;

function TAVLTreeNode<TREE_CONSTRAINTS, TTree>.TreeDepth: integer;
// longest WAY down. e.g. only one node => 0 !
var LeftDepth, RightDepth: integer;
begin
  if Left<>nil then
    LeftDepth:=Left.TreeDepth+1
  else
    LeftDepth:=0;
  if Right<>nil then
    RightDepth:=Right.TreeDepth+1
  else
    RightDepth:=0;
  if LeftDepth>RightDepth then
    Result:=LeftDepth
  else
    Result:=RightDepth;
end;

procedure TAVLTreeNode<TREE_CONSTRAINTS, TTree>.ConsistencyCheck(ATree: TObject);
var
  LTree: TTree absolute ATree;
  LeftDepth: SizeInt;
  RightDepth: SizeInt;
begin
  // test left child
  if Left<>nil then begin
    if Left.Parent<>@Self then
      raise EAVLTree.Create('Left.Parent<>Self');
    if LTree.Compare(Left.Data.Key,Data.Key)>0 then
      raise EAVLTree.Create('Compare(Left.Data,Data)>0');
    Left.ConsistencyCheck(LTree);
  end;
  // test right child
  if Right<>nil then begin
    if Right.Parent<>@Self then
      raise EAVLTree.Create('Right.Parent<>Self');
    if LTree.Compare(Data.Key,Right.Data.Key)>0 then
      raise EAVLTree.Create('Compare(Data,Right.Data)>0');
    Right.ConsistencyCheck(LTree);
  end;
  // test balance
  if Left<>nil then
    LeftDepth:=Left.TreeDepth+1
  else
    LeftDepth:=0;
  if Right<>nil then
    RightDepth:=Right.TreeDepth+1
  else
    RightDepth:=0;
  if Balance<>(LeftDepth-RightDepth) then
    raise EAVLTree.CreateFmt('Balance[%d]<>(RightDepth[%d]-LeftDepth[%d])', [Balance, RightDepth, LeftDepth]);
end;

function TAVLTreeNode<TREE_CONSTRAINTS, TTree>.GetCount: SizeInt;
begin
  Result:=1;
  if Assigned(Left) then Inc(Result,Left.GetCount);
  if Assigned(Right) then Inc(Result,Right.GetCount);
end;

{ TCustomTreeEnumerator<T, PNode, TTree> }

function TCustomTreeEnumerator<T, PNode, TTree>.DoGetCurrent: T;
begin
  Result := GetCurrent;
end;

constructor TCustomTreeEnumerator<T, PNode, TTree>.Create(ATree: TObject);
begin
  TObject(FTree) := ATree;
end;

{ TTreeEnumerable<TTreeEnumerator, TTreePointersEnumerator, T, PT, TREE_CONSTRAINTS>.TPointersCollection }

function TTreeEnumerable<TTreeEnumerator, TTreePointersEnumerator, T, PT, PNode, TTree>.
  TPointersCollection.Tree: TTree;
begin
  Result := TTree(Pointer(@Self)^);
end;

function TTreeEnumerable<TTreeEnumerator, TTreePointersEnumerator, T, PT, PNode, TTree>.
  TPointersCollection.GetCount: SizeInt;
begin
  Result := Tree.Count;
end;

function TTreeEnumerable<TTreeEnumerator, TTreePointersEnumerator, T, PT, PNode, TTree>.
  TPointersCollection.{Do}GetEnumerator: TTreePointersEnumerator;
begin
  Result := TTreePointersEnumerator(TTreePointersEnumerator.NewInstance);
  TCustomTreeEnumerator<PT, PNode, TTree>(Result).Create(Tree);
end;

function TTreeEnumerable<TTreeEnumerator, TTreePointersEnumerator, T, PT, PNode, TTree>.
  TPointersCollection.ToArray: TArray<PT>;
var
  i: SizeInt;
  LEnumerator: TTreePointersEnumerator;
begin
  SetLength(Result, Count);

  try
    LEnumerator := GetEnumerator;

    i := 0;
    while LEnumerator.MoveNext do
    begin
      Result[i] := LEnumerator.Current;
      Inc(i);
    end;
  finally
    LEnumerator.Free;
  end;
end;

{ TTreeEnumerable<TTreeEnumerator, TTreePointersEnumerator, T, PT, TREE_CONSTRAINTS> }

function TTreeEnumerable<TTreeEnumerator, TTreePointersEnumerator, T, PT, PNode, TTree>.GetCount: SizeInt;
begin
  Result := FTree.Count;
end;

function TTreeEnumerable<TTreeEnumerator, TTreePointersEnumerator, T, PT, PNode, TTree>.GetPointers: PPointersCollection;
begin
  Result := @FPointers;
end;

constructor TTreeEnumerable<TTreeEnumerator, TTreePointersEnumerator, T, PT, PNode, TTree>.Create(
  ATree: TTree);
begin
  FTree := ATree;
end;

function TTreeEnumerable<TTreeEnumerator, TTreePointersEnumerator, T, PT, PNode, TTree>.
  DoGetEnumerator: TTreeEnumerator;
begin
  Result := TTreeEnumerator(TTreeEnumerator.NewInstance);
  TTreeEnumerator(Result).Create(FTree);
end;

function TTreeEnumerable<TTreeEnumerator, TTreePointersEnumerator, T, PT, PNode, TTree>.ToArray: TArray<T>;
begin
  Result := ToArrayImpl(FTree.Count);
end;

{ TAVLTreeEnumerator<T, PNode, TTree> }

function TAVLTreeEnumerator<T, PNode, TTree>.DoMoveNext: Boolean;
begin
  if FLowToHigh then begin
    if FCurrent<>nil then
      FCurrent:=FCurrent.Successor
    else
      FCurrent:=FTree.FindLowest;
  end else begin
    if FCurrent<>nil then
      FCurrent:=FCurrent.Precessor
    else
      FCurrent:=FTree.FindHighest;
  end;
  Result:=FCurrent<>nil;
end;

constructor TAVLTreeEnumerator<T, PNode, TTree>.Create(ATree: TObject; ALowToHigh: boolean);
begin
  inherited Create(ATree);
  FLowToHigh:=aLowToHigh;
end;

{ TCustomAVLTreeMap<TREE_CONSTRAINTS>.TPairEnumerator }

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.TPairEnumerator.GetCurrent: TTreePair;
begin
  Result := TTreePair((@FCurrent.Data)^);
end;

{ TCustomAVLTreeMap<TREE_CONSTRAINTS>.TNodeEnumerator }

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.TNodeEnumerator.GetCurrent: PNode;
begin
  Result := FCurrent;
end;

{ TCustomAVLTreeMap<TREE_CONSTRAINTS>.TKeyEnumerator }

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.TKeyEnumerator.GetCurrent: TKey;
begin
  Result := FCurrent.Key;
end;

{ TCustomAVLTreeMap<TREE_CONSTRAINTS>.TValueEnumerator }

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.TValueEnumerator.GetCurrent: TValue;
begin
  Result := FCurrent.Value;
end;

{ TCustomAVLTreeMap<TREE_CONSTRAINTS> }

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.NodeAdded(ANode: PNode);
begin
end;

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.DeletingNode(ANode: PNode; AOrigin: boolean);
begin
end;

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.DeleteNode(ANode: PNode);
begin
  if ANode.Left<>nil then
    DeleteNode(ANode.Left, true);
  if ANode.Right<>nil then
    DeleteNode(ANode.Right, true);
  Dispose(ANode);
end;

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.Compare(constref ALeft, ARight: TKey): Integer; inline;
begin
  Result := FComparer.Compare(ALeft, ARight);
end;

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.FindPredecessor(ANode: PNode): PNode;
begin
  if ANode <> nil then
  begin
    if ANode.Left <> nil then
    begin
      ANode := ANode.Left;
      while ANode.Right <> nil do ANode := ANode.Right;
    end
    else
    repeat
      Result := ANode;
      ANode := ANode.Parent;
    until (ANode = nil) or (ANode.Right = Result);
  end;
  Result := ANode;
end;

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.RotateRightRight(ANode: PNode);
var
  LNode, LParent: PNode;
begin
  LNode := ANode.Right;
  LParent := ANode.Parent;

  ANode.Right := LNode.Left;
  if ANode.Right <> nil then
    ANode.Right.Parent := ANode;

  LNode.Left := ANode;
  LNode.Parent := LParent;
  ANode.Parent := LNode;

  if LParent <> nil then
  begin
    if LParent.Left = ANode then
      LParent.Left := LNode
    else
      LParent.Right := LNode;
  end
  else
    FRoot := LNode;

  if LNode.Balance = -1 then
  begin
    ANode.Balance := 0;
    LNode.Balance := 0;
  end
  else
  begin
    ANode.Balance := -1;
    LNode.Balance := 1;
  end
end;

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.RotateLeftLeft(ANode: PNode);
var
  LNode, LParent: PNode;
begin
  LNode := ANode.Left;
  LParent := ANode.Parent;

  ANode.Left := LNode.Right;
  if ANode.Left <> nil then
    ANode.Left.Parent := ANode;

  LNode.Right := ANode;
  LNode.Parent := LParent;
  ANode.Parent := LNode;

  if LParent <> nil then
  begin
    if LParent.Left = ANode then
      LParent.Left := LNode
    else
      LParent.Right := LNode;
  end
  else
    FRoot := LNode;

  if LNode.Balance = 1 then
  begin
    ANode.Balance := 0;
    LNode.Balance := 0;
  end
  else
  begin
    ANode.Balance := 1;
    LNode.Balance := -1;
  end
end;

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.RotateRightLeft(ANode: PNode);
var
  LRight, LLeft, LParent: PNode;
begin
  LRight := ANode.Right;
  LLeft := LRight.Left;
  LParent := ANode.Parent;

  LRight.Left := LLeft.Right;
  if LRight.Left <> nil then
    LRight.Left.Parent := LRight;

  ANode.Right := LLeft.Left;
  if ANode.Right <> nil then
    ANode.Right.Parent := ANode;

  LLeft.Left := ANode;
  LLeft.Right := LRight;
  ANode.Parent := LLeft;
  LRight.Parent := LLeft;

  LLeft.Parent := LParent;

  if LParent <> nil then
  begin
    if LParent.Left = ANode then
      LParent.Left := LLeft
    else
      LParent.Right := LLeft;
  end
  else
    FRoot := LLeft;

  if LLeft.Balance = -1 then
    ANode.Balance := 1
  else
    ANode.Balance := 0;

  if LLeft.Balance = 1 then
    LRight.Balance := -1
  else
    LRight.Balance := 0;

  LLeft.Balance := 0;
end;

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.RotateLeftRight(ANode: PNode);
var
  LLeft, LRight, LParent: PNode;
begin
  LLeft := ANode.Left;
  LRight := LLeft.Right;
  LParent := ANode.Parent;

  LLeft.Right := LRight.Left;
  if LLeft.Right <> nil then
    LLeft.Right.Parent := LLeft;

  ANode.Left := LRight.Right;
  if ANode.Left <> nil then
    ANode.Left.Parent := ANode;

  LRight.Right := ANode;
  LRight.Left := LLeft;
  ANode.Parent := LRight;
  LLeft.Parent := LRight;

  LRight.Parent := LParent;

  if LParent <> nil then
  begin
    if LParent.Left = ANode then
      LParent.Left := LRight
    else
      LParent.Right := LRight;
  end
  else
    FRoot := LRight;

  if LRight.Balance =  1 then
    ANode.Balance := -1
  else
    ANode.Balance := 0;
  if LRight.Balance = -1 then
    LLeft.Balance :=  1
  else
    LLeft.Balance := 0;

  LRight.Balance := 0;
end;

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.WriteStr(AStream: TStream; const AText: string);
begin
  if AText='' then exit;
  AStream.Write(AText[1],Length(AText));
end;

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.GetNodeCollection: TNodeCollection;
begin
  if not Assigned(FNodes) then
    FNodes := TNodeCollection.Create(TTree(Self));
  Result := FNodes;
end;

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.InternalDelete(ANode: PNode);
var
  t, y, z: PNode;
  LNest: boolean;
begin
  if (ANode.Left <> nil) and (ANode.Right <> nil) then
  begin
    y := FindPredecessor(ANode);
    y.Info := ANode.Info;
    DeletingNode(y, false);
    InternalDelete(y);
    LNest := false;
  end
  else
  begin
    if ANode.Left <> nil then
    begin
      y := ANode.Left;
      ANode.Left := nil;
    end
    else
    begin
      y := ANode.Right;
      ANode.Right := nil;
    end;
    ANode.Balance := 0;
    LNest  := true;
  end;

  if y <> nil then
  begin
    y.Parent := ANode.Parent;
    y.Left  := ANode.Left;
    if y.Left <> nil then
      y.Left.Parent := y;
    y.Right := ANode.Right;
    if y.Right <> nil then
      y.Right.Parent := y;
    y.Balance := ANode.Balance;
  end;

  if ANode.Parent <> nil then
  begin
    if ANode.Parent.Left = ANode then
      ANode.Parent.Left := y
    else
      ANode.Parent.Right := y;
  end
  else
    FRoot := y;

  if LNest then
  begin
    z := y;
    y := ANode.Parent;
    while y <> nil do
    begin
      if y.Balance = 0 then
      begin
        if y.Left = z then
          y.Balance := -1
        else
          y.Balance := 1;
        break;
      end
      else
      begin
        if ((y.Balance = 1) and (y.Left = z)) or ((y.Balance = -1) and (y.Right = z)) then
        begin
          y.Balance := 0;
          z := y;
          y := y.Parent;
        end
        else
        begin
          if y.Left = z then
            t := y.Right
          else
            t := y.Left;
          if t.Balance = 0 then
          begin
            if y.Balance = 1 then
              RotateLeftLeft(y)
            else
              RotateRightRight(y);
            break;
          end
          else if y.Balance = t.Balance then
          begin
            if y.Balance = 1 then
              RotateLeftLeft(y)
            else
              RotateRightRight(y);
            z := t;
            y := t.Parent;
          end
          else
          begin
            if y.Balance = 1 then
              RotateLeftRight(y)
            else
              RotateRightLeft(y);
            z := y.Parent;
            y := z.Parent;
          end
        end
      end
    end
  end;
end;

constructor TCustomAVLTreeMap<TREE_CONSTRAINTS>.Create;
begin
  FComparer := TComparer<TKey>.Default;
end;

destructor TCustomAVLTreeMap<TREE_CONSTRAINTS>.Destroy;
begin
  FNodes.Free;
  Clear;
end;

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.Add(constref AKey: TKey; constref AValue: TValue): PNode;
var
  LParent, LNode: PNode;
begin
  Inc(FCount);
  Result := AddNode;
  Result.Data.Key := AKey;
  Result.Data.Value := AValue;

  LParent := FRoot;
  if LParent = nil then // first item in tree
  begin
    FRoot := Result;
    NodeAdded(Result);
    Exit;
  end;

  // insert new node

  while true do
    if Compare(Result.Key,LParent.Key)<0 then
    begin
      if LParent.Left = nil then
      begin
        LParent.Left := Result;
        Break;
      end;
      LParent := LParent.Left;
    end
    else
    begin
      if LParent.Right = nil then
      begin
        LParent.Right := Result;
        Break;
      end;
      LParent := LParent.Right;
    end;

  Result.Parent := LParent;

  NodeAdded(Result);

  // balance after insert

  if LParent.Balance<>0 then
    LParent.Balance := 0
  else
  begin
    if LParent.Left = Result then
      LParent.Balance := 1
    else
      LParent.Balance := -1;

    LNode := LParent.Parent;

    while LNode <> nil do
    begin
      if LNode.Balance<>0 then
      begin
        if LNode.Balance = 1 then
        begin
          if LNode.Right = LParent then
            LNode.Balance := 0
          else if LParent.Balance = -1 then
            RotateLeftRight(LNode)
          else
            RotateLeftLeft(LNode);
        end
        else
        begin
          if LNode.Left = LParent then
            LNode.Balance := 0
          else if LParent^.Balance = 1 then
            RotateRightLeft(LNode)
          else
            RotateRightRight(LNode);
        end;
        Break;
      end;

      if LNode.Left = LParent then
        LNode.Balance := 1
      else
        LNode.Balance := -1;

      LParent := LNode;
      LNode := LNode.Parent;
    end;
  end;
end;

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.Remove(constref AKey: TKey): boolean;
var
  LNode: PNode;
begin
  LNode:=Find(AKey);
  if LNode<>nil then begin
    Delete(LNode);
    Result:=true;
  end else
    Result:=false;
end;

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.Delete(ANode: PNode; ADispose: boolean);
begin
  if (ANode.Left = nil) or (ANode.Right = nil) then
    DeletingNode(ANode, true);

  InternalDelete(ANode);

  DeleteNode(ANode, ADispose);
  Dec(FCount);
end;

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.Clear(ADisposeNodes: Boolean);
begin
  if (FRoot<>nil) and ADisposeNodes then
    DeleteNode(FRoot);
  fRoot:=nil;
  FCount:=0;
end;

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.GetEnumerator: TPairEnumerator;
begin
  Result := TPairEnumerator.Create(Self, true);
end;

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.FindLowest: PNode;
begin
  Result:=FRoot;
  if Result<>nil then
    while Result.Left<>nil do Result:=Result.Left;
end;

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.FindHighest: PNode;
begin
  Result:=FRoot;
  if Result<>nil then
    while Result.Right<>nil do Result:=Result.Right;
end;

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.Find(constref AKey: TKey): PNode;
var
  LComp: SizeInt;
begin
  Result:=FRoot;
  while (Result<>nil) do
  begin
    LComp:=Compare(AKey,Result.Key);
    if LComp=0 then
      Exit;
    if LComp<0 then
      Result:=Result.Left
    else
      Result:=Result.Right
  end;
end;

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.ConsistencyCheck;
var
  RealCount: SizeInt;
begin
  RealCount:=0;
  if FRoot<>nil then begin
    FRoot.ConsistencyCheck(Self);
    RealCount:=FRoot.GetCount;
  end;
  if Count<>RealCount then
    raise EAVLTree.Create('Count<>RealCount');
end;

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.WriteTreeNode(AStream: TStream; ANode: PNode);
var
  b: String;
  IsLeft: boolean;
  LParent: PNode;
  WasLeft: Boolean;
begin
  if ANode=nil then exit;
  WriteTreeNode(AStream, ANode.Right);
  LParent:=ANode;
  WasLeft:=false;
  b:='';
  while LParent<>nil do begin
    if LParent.Parent=nil then begin
      if LParent=ANode then
        b:='--'+b
      else
        b:='  '+b;
      break;
    end;
    IsLeft:=LParent.Parent.Left=LParent;
    if LParent=ANode then begin
      if IsLeft then
        b:='\-'
      else
        b:='/-';
    end else begin
      if WasLeft=IsLeft then
        b:='  '+b
      else
        b:='| '+b;
    end;
    WasLeft:=IsLeft;
    LParent:=LParent.Parent;
  end;
  b:=b+NodeToReportStr(ANode)+LineEnding;
  WriteStr(AStream, b);
  WriteTreeNode(AStream, ANode.Left);
end;

procedure TCustomAVLTreeMap<TREE_CONSTRAINTS>.WriteReportToStream(AStream: TStream);
begin
  WriteStr(AStream, '-Start-of-AVL-Tree-------------------'+LineEnding);
  WriteTreeNode(AStream, fRoot);
  WriteStr(AStream, '-End-Of-AVL-Tree---------------------'+LineEnding);
end;

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.NodeToReportStr(ANode: PNode): string;
begin
  Result:=Format(' Self=%p  Parent=%p  Balance=%d', [ANode, ANode.Parent, ANode.Balance]);
end;

function TCustomAVLTreeMap<TREE_CONSTRAINTS>.ReportAsString: string;
var ms: TMemoryStream;
begin
  Result:='';
  ms:=TMemoryStream.Create;
  try
    WriteReportToStream(ms);
    ms.Position:=0;
    SetLength(Result,ms.Size);
    if Result<>'' then
      ms.Read(Result[1],length(Result));
  finally
    ms.Free;
  end;
end;

{ TAVLTreeMap<TKey, TValue> }

function TAVLTreeMap<TKey, TValue>.AddNode: PNode;
begin
  Result := New(PNode);
  Result^ := Default(TNode);
end;

procedure TAVLTreeMap<TKey, TValue>.DeleteNode(ANode: PNode; ADispose: boolean = true);
begin
  if ADispose then
    Dispose(ANode);
end;

{ TIndexedAVLTreeMap<TKey, TValue> }

procedure TIndexedAVLTreeMap<TKey, TValue>.RotateRightRight(ANode: PNode);
var
  LOldRight: PNode;
begin
  LOldRight:=ANode.Right;
  inherited;
  Inc(LOldRight.Data.Info, (1 + ANode.Data.Info));
end;

procedure TIndexedAVLTreeMap<TKey, TValue>.RotateLeftLeft(ANode: PNode);
var
  LOldLeft: PNode;
begin
  LOldLeft:=ANode.Left;
  inherited;
  Dec(ANode.Data.Info, (1 + LOldLeft.Data.Info));
end;

procedure TIndexedAVLTreeMap<TKey, TValue>.RotateRightLeft(ANode: PNode);
var
  LB, LC: PNode;
begin
  LB := ANode.Right;
  LC := LB.Left;
  inherited;
  Dec(LB.Data.Info, 1+LC.Info);
  Inc(LC.Data.Info, 1+ANode.Info);
end;

procedure TIndexedAVLTreeMap<TKey, TValue>.RotateLeftRight(ANode: PNode);
var
  LB, LC: PNode;
begin
  LB := ANode.Left;
  LC := LB.Right;
  inherited;
  Inc(LC.Data.Info, 1+LB.Info);
  Dec(ANode.Data.Info, 1+LC.Info);
end;


procedure TIndexedAVLTreeMap<TKey, TValue>.NodeAdded(ANode: PNode);
var
  LParent, LNode: PNode;
begin
  FLastNode := nil;
  LNode := ANode;
  repeat
    LParent:=LNode.Parent;
    if (LParent=nil) then break;
    if LParent.Left=LNode then
      Inc(LParent.Data.Info);
    LNode:=LParent;
  until false;
end;

procedure TIndexedAVLTreeMap<TKey, TValue>.DeletingNode(ANode: PNode; AOrigin: boolean);
var
  LParent: PNode;
begin
  if not AOrigin then
    Dec(ANode.Data.Info);
  FLastNode := nil;
  repeat
    LParent:=ANode.Parent;
    if (LParent=nil) then exit;
    if LParent.Left=ANode then
      Dec(LParent.Data.Info);
    ANode:=LParent;
  until false;
end;

function TIndexedAVLTreeMap<TKey, TValue>.AddNode: PNode;
begin
  Result := PNode(New(PNode));
  Result^ := Default(TNode);
end;

procedure TIndexedAVLTreeMap<TKey, TValue>.DeleteNode(ANode: PNode; ADispose: boolean = true);
begin
  if ADispose then
    Dispose(ANode);
end;

function TIndexedAVLTreeMap<TKey, TValue>.GetNodeAtIndex(AIndex: SizeInt): PNode;
begin
  if (AIndex<0) or (AIndex>=Count) then
    raise EIndexedAVLTree.CreateFmt('TIndexedAVLTree: AIndex %d out of bounds 0..%d', [AIndex, Count]);

  if FLastNode<>nil then begin
    if AIndex=FLastIndex then
      Exit(FLastNode)
    else if AIndex=FLastIndex+1 then begin
      FLastIndex:=AIndex;
      FLastNode:=FLastNode.Successor;
      Exit(FLastNode);
    end else if AIndex=FLastIndex-1 then begin
      FLastIndex:=AIndex;
      FLastNode:=FLastNode.Precessor;
      Exit(FLastNode);
    end;
  end;

  FLastIndex:=AIndex;
  Result:=FRoot;
  repeat
    if Result.Info>AIndex then
      Result:=Result.Left
    else if Result.Info=AIndex then begin
      FLastNode:=Result;
      Exit;
    end
    else begin
      Dec(AIndex, Result.Info+1);
      Result:=Result.Right;
    end;
  until false;
end;

function TIndexedAVLTreeMap<TKey, TValue>.NodeToIndex(ANode: PNode): SizeInt;
var
  LNode: PNode;
  LParent: PNode;
begin
  if ANode=nil then
    Exit(-1);

  if FLastNode=ANode then
    Exit(FLastIndex);

  LNode:=ANode;
  Result:=LNode.Info;
  repeat
    LParent:=LNode.Parent;
    if LParent=nil then break;
    if LParent.Right=LNode then
      inc(Result,LParent.Info+1);
    LNode:=LParent;
  until false;

  FLastNode:=ANode;
  FLastIndex:=Result;
end;

procedure TIndexedAVLTreeMap<TKey, TValue>.ConsistencyCheck;
var
  LNode: PNode;
  i: SizeInt;
  LeftCount: SizeInt = 0;
begin
  inherited ConsistencyCheck;
  i:=0;
  for LNode in Self.Nodes do
  begin
    if LNode.Left<>nil then
      LeftCount:=LNode.Left.GetCount
    else
      LeftCount:=0;

    if LNode.Info<>LeftCount then
      raise EIndexedAVLTree.CreateFmt('LNode.LeftCount=%d<>%d',[LNode.Info,LeftCount]);

    if GetNodeAtIndex(i)<>LNode then
      raise EIndexedAVLTree.CreateFmt('GetNodeAtIndex(%d)<>%P',[i,LNode]);
    FLastNode:=nil;
    if GetNodeAtIndex(i)<>LNode then
      raise EIndexedAVLTree.CreateFmt('GetNodeAtIndex(%d)<>%P',[i,LNode]);

    if NodeToIndex(LNode)<>i then
      raise EIndexedAVLTree.CreateFmt('NodeToIndex(%P)<>%d',[LNode,i]);
    FLastNode:=nil;
    if NodeToIndex(LNode)<>i then
      raise EIndexedAVLTree.CreateFmt('NodeToIndex(%P)<>%d',[LNode,i]);

    inc(i);
  end;
end;

function TIndexedAVLTreeMap<TKey, TValue>.NodeToReportStr(ANode: PNode): string;
begin
  Result:=Format(' Self=%p  Parent=%p  Balance=%d Idx=%d Info=%d',
             [ANode,ANode.Parent, ANode.Balance, NodeToIndex(ANode), ANode.Info]);
end;

{ TAVLTree<T> }

function TAVLTree<T>.Add(constref AValue: T): PNode;
begin
  Result := inherited Add(AValue, EmptyRecord);
end;

{ TIndexedAVLTree<T> }

function TIndexedAVLTree<T>.Add(constref AValue: T): PNode;
begin
  Result := inherited Add(AValue, EmptyRecord);
end;

{ TSortedHashSet<T>.TSortedHashSetEnumerator }

function TSortedHashSet<T>.TSortedHashSetEnumerator.DoMoveNext: boolean;
begin
  Result := TTreeEnumerator(FEnumerator).DoMoveNext;
end;

function TSortedHashSet<T>.TSortedHashSetEnumerator.DoGetCurrent: T;
begin
  Result := TTreeEnumerator(FEnumerator).DoGetCurrent.Key;
end;

function TSortedHashSet<T>.TSortedHashSetEnumerator.GetCurrent: T;
begin
  Result := TTreeEnumerator(FEnumerator).GetCurrent.Key;
end;

constructor TSortedHashSet<T>.TSortedHashSetEnumerator.Create(ASet: TSortedHashSet<T>);
begin
  FEnumerator := ASet.FInternalTree.Nodes.DoGetEnumerator;
end;

destructor TSortedHashSet<T>.TSortedHashSetEnumerator.Destroy;
begin
  FEnumerator.Free;
end;

{ TSortedHashSet<T> }

function TSortedHashSet<T>.DoGetEnumerator: TEnumerator<T>;
begin
  Result := GetEnumerator;
end;

procedure TSortedHashSet<T>.InitializeSet;
begin
  inherited;
  FInternalTree := TAVLTree<T>.Create;
end;

function TSortedHashSet<T>.GetEnumerator: THashSetEnumerator;
begin
  Result := TSortedHashSetEnumerator.Create(Self);
end;

function TSortedHashSet<T>.Add(constref AValue: T): Boolean;
begin
  Result := inherited;
  if Result then
    FInternalTree.Add(AValue);
end;

function TSortedHashSet<T>.Remove(constref AValue: T): Boolean;
begin
  Result := inherited;
  if Result then
    FInternalTree.Remove(AValue);
end;

destructor TSortedHashSet<T>.Destroy;
begin
  FInternalTree.Free;
  inherited;
end;

end.
