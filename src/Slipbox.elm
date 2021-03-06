module Slipbox exposing 
  ( Slipbox
  , new
  , getNotesAndLinks
  , getNotes
  , getSources
  , getItems
  , getLinkedNotes
  , getNotesThatCanLinkToNote
  , getNotesAssociatedToSource
  , compressNote
  , expandNote
  , AddAction(..)
  , addItem
  , dismissItem
  , updateItem
  , UpdateAction(..)
  , tick
  , simulationIsCompleted
  , decode
  , encode
  )

import Note
import Link
import Item
import Source
import IdGenerator
import Json.Encode
import Json.Decode
import Force

--Types
type Slipbox = Slipbox Content

type alias Content =
  { notes: List Note.Note
  , links: List Link.Link
  , items: List Item.Item
  , sources: List Source.Source
  , state: State Int
  , idGenerator: IdGenerator.IdGenerator
  }

getContent : Slipbox -> Content
getContent slipbox =
  case slipbox of 
    Slipbox content -> content

-- Returns Slipbox

new :  Slipbox
new  =
  let
    ( state, _ ) = simulation [] []
  in
  Slipbox <| Content [] [] [] [] state IdGenerator.init

getNotesAndLinks : (Maybe String) -> Slipbox -> ((List Note.Note), (List Link.Link))
getNotesAndLinks maybeSearch slipbox =
  let
      content = getContent slipbox
  in
  case maybeSearch of
    Just search -> 
      let
        filteredNotes = List.filter ( Note.contains search ) content.notes
        relevantLinks = List.filter ( linkIsRelevant filteredNotes ) content.links
      in
      ( filteredNotes,  relevantLinks )
    Nothing -> ( content.notes, content.links )

getNotes : (Maybe String) -> Slipbox -> (List Note.Note)
getNotes maybeSearch slipbox =
  let
    content = getContent slipbox
  in
  case maybeSearch of
    Just search -> List.filter (Note.contains search) content.notes
    Nothing -> content.notes

getSources : (Maybe String) -> Slipbox -> (List Source.Source)
getSources maybeSearch slipbox =
  let
    content = getContent slipbox
  in
  case maybeSearch of
    Just search -> List.filter (Source.contains search) content.sources
    Nothing -> content.sources

getItems : Slipbox -> (List Item.Item)
getItems slipbox =
  .items <| getContent slipbox

getLinkedNotes : Note.Note -> Slipbox -> ( List ( Note.Note, Link.Link ) )
getLinkedNotes note slipbox =
  let
      content = getContent slipbox
      relevantLinks = List.filter ( isAssociated note ) content.links
  in
  List.filterMap ( convertLinktoLinkNoteTuple note content.notes ) relevantLinks

convertLinktoLinkNoteTuple : Note.Note -> ( List Note.Note ) -> Link.Link -> ( Maybe ( Note.Note, Link.Link ) )
convertLinktoLinkNoteTuple targetNote notes link =
  if Link.isTarget link targetNote then
    case List.head <| List.filter ( Link.isSource link ) notes of
      Just note -> Just ( note, link )
      Nothing -> Nothing
  else if Link.isSource link targetNote then
    case List.head <| List.filter ( Link.isTarget link ) notes of
      Just note -> Just ( note, link )
      Nothing -> Nothing
  else
    Nothing

getNotesThatCanLinkToNote : Note.Note -> Slipbox -> (List Note.Note)
getNotesThatCanLinkToNote note slipbox =
  let
      content = getContent slipbox
  in
  List.filter ( Link.canLink content.links note )
    <| List.filter (\n -> not <|  Note.is note n ) content.notes

getNotesAssociatedToSource : Source.Source -> Slipbox -> (List Note.Note)
getNotesAssociatedToSource source slipbox =
  List.filter ( Note.isAssociated source ) <| .notes <| getContent slipbox

compressNote : Note.Note -> Slipbox -> Slipbox
compressNote note slipbox =
  let
    content = getContent slipbox
    conditionallyCompressNote = \n -> if Note.is note n then Note.compress n else n
    (state, notes) = simulation
      (List.map conditionallyCompressNote content.notes)
      content.links
  in
  Slipbox { content | notes = notes, state = state}

expandNote : Note.Note -> Slipbox -> Slipbox
expandNote note slipbox =
  let
      content = getContent slipbox
      conditionallyExpandNote = \n -> if Note.is note n then Note.expand n else n
      (state, notes) = simulation
        (List.map conditionallyExpandNote content.notes)
        content.links
  in
  Slipbox { content | notes = notes, state = state}

type AddAction
  = OpenNote Note.Note
  | OpenSource Source.Source
  | NewNote
  | NewSource
  | NewQuestion

addItem : ( Maybe Item.Item ) -> AddAction -> Slipbox -> Slipbox
addItem maybeItem addAction slipbox =
  let
    content = getContent slipbox

    itemExistsLambda = \existingItem ->
      let
        updatedContent = getContent <| dismissItem existingItem slipbox
      in
      case maybeItem of
        Just itemToMatch -> Slipbox { updatedContent | items = List.foldr (buildItemList itemToMatch existingItem) [] updatedContent.items }
        Nothing -> Slipbox { updatedContent | items = existingItem :: updatedContent.items }

    itemDoesNotExistLambda = \(newItem,idGenerator) ->
      case maybeItem of
       Just itemToMatch -> Slipbox { content | items = List.foldr (buildItemList itemToMatch newItem) [] content.items
        , idGenerator = idGenerator
        }
       Nothing -> Slipbox { content | items = newItem :: content.items, idGenerator = idGenerator }
  in
  case addAction of
    OpenNote note ->
      case tryFindItemFromComponent content.items <| hasNote note of
        Just existingItem -> itemExistsLambda existingItem
        Nothing -> itemDoesNotExistLambda <| Item.openNote content.idGenerator note

    OpenSource source ->
      case tryFindItemFromComponent content.items <| hasSource source of
        Just existingItem -> itemExistsLambda existingItem
        Nothing -> itemDoesNotExistLambda <| Item.openSource content.idGenerator source

    NewNote -> itemDoesNotExistLambda <| Item.newNote content.idGenerator

    NewSource -> itemDoesNotExistLambda <| Item.newSource content.idGenerator

    NewQuestion -> itemDoesNotExistLambda <| Item.newQuestion content.idGenerator

dismissItem : Item.Item -> Slipbox -> Slipbox
dismissItem item slipbox =
  let
      content = getContent slipbox
  in
  Slipbox { content | items = removeItemFromList item content.items }

removeItemFromList : Item.Item -> ( List (Item.Item ) ) -> ( List ( Item.Item ) )
removeItemFromList item items =
  List.filter ( isNotLambda Item.is item ) items

type UpdateAction
  = UpdateContent String
  | UpdateSource String
  | UpdateTitle String
  | UpdateAuthor String
  | UpdateSearch String
  | AddLink Note.Note
  | Edit
  | PromptConfirmDelete
  | AddLinkForm
  | PromptConfirmRemoveLink Note.Note Link.Link
  | Cancel
  | Submit
  | OpenTray
  | CloseTray

updateItem : Item.Item -> UpdateAction -> Slipbox -> Slipbox
updateItem item updateAction slipbox =
  let
      content = getContent slipbox
      update = \updatedItem -> Slipbox 
        { content | items = List.map (conditionalUpdate updatedItem (Item.is item)) content.items}
  in
  case updateAction of
    UpdateContent input ->
      case item of
        Item.EditingNote itemId tray originalNote noteWithEdits ->
          update <| Item.EditingNote itemId tray originalNote
            <| Note.updateContent input noteWithEdits
        Item.EditingSource itemId tray originalSource sourceWithEdits ->
          update <| Item.EditingSource itemId tray originalSource
            <| Source.updateContent input sourceWithEdits
        Item.NewNote itemId tray newNoteContent ->
          update <| Item.NewNote itemId tray { newNoteContent | content = input }
        Item.NewSource itemId tray newSourceContent ->
          update <| Item.NewSource itemId tray { newSourceContent | content = input }
        Item.NewQuestion itemId tray _ ->
          update <| Item.NewQuestion itemId tray input
        _ -> slipbox

    UpdateSource input ->
      case item of
        Item.EditingNote itemId tray originalNote noteWithEdits ->
          update
            <| Item.EditingNote itemId tray originalNote
              <| Note.updateSource input noteWithEdits
        Item.NewNote itemId tray newNoteContent ->
          update <| Item.NewNote itemId tray { newNoteContent | source = input }
        _ -> slipbox

    UpdateTitle input ->
      case item of
        Item.EditingSource itemId tray originalSource sourceWithEdits ->
          update <| Item.EditingSource itemId tray originalSource
            <| Source.updateTitle input sourceWithEdits
        Item.NewSource itemId tray newSourceContent ->
          update <| Item.NewSource itemId tray { newSourceContent | title = input }
        _ -> slipbox

    UpdateAuthor input ->
      case item of
        Item.EditingSource itemId tray originalSource sourceWithEdits ->
          update <| Item.EditingSource itemId tray originalSource
            <| Source.updateAuthor input sourceWithEdits
        Item.NewSource itemId tray newSourceContent ->
          update <| Item.NewSource itemId tray { newSourceContent | author = input }
        _ -> slipbox

    UpdateSearch input ->
      case item of 
        Item.AddingLinkToNoteForm itemId tray _ note maybeNote ->
          update <| Item.AddingLinkToNoteForm itemId tray input note maybeNote
        _ -> slipbox

    AddLink noteToBeAdded ->
      case item of 
        Item.AddingLinkToNoteForm itemId tray search note _ ->
          update <| Item.AddingLinkToNoteForm itemId tray search note <| Just noteToBeAdded
        _ -> slipbox

    Edit ->
      case item of
        Item.Note itemId tray note ->
          update <| Item.EditingNote itemId tray note note
        Item.Source itemId tray source ->
          update <| Item.EditingSource itemId tray source source
        _ -> slipbox
            
    PromptConfirmDelete ->
      case item of
        Item.Note itemId tray note ->
          update <| Item.ConfirmDeleteNote itemId tray note
        Item.Source itemId tray source ->
          update <| Item.ConfirmDeleteSource itemId tray source
        _ -> slipbox

    AddLinkForm ->
      case item of 
        Item.Note itemId tray note ->
          update <| Item.AddingLinkToNoteForm itemId tray "" note Nothing
        _ -> slipbox
    
    PromptConfirmRemoveLink linkedNote link ->
      case item of 
        Item.Note itemId tray note ->
          update <| Item.ConfirmDeleteLink itemId tray note linkedNote link
        _ -> slipbox
    
    Cancel ->
      case item of
        Item.NewNote itemId tray note ->
          update <| Item.ConfirmDiscardNewNoteForm itemId tray note
        Item.ConfirmDiscardNewNoteForm itemId tray note ->
          update <| Item.NewNote itemId tray note
        Item.EditingNote itemId tray originalNote _ ->
          update <| Item.Note itemId tray originalNote
        Item.ConfirmDeleteNote itemId tray note ->
          update <| Item.Note itemId tray note
        Item.AddingLinkToNoteForm itemId tray _ note _ ->
          update <| Item.Note itemId tray note
        Item.NewSource itemId tray source ->
          update <| Item.ConfirmDiscardNewSourceForm itemId tray source
        Item.ConfirmDiscardNewSourceForm itemId tray source ->
          update <| Item.NewSource itemId tray source
        Item.EditingSource itemId tray originalSource _ ->
          update <| Item.Source itemId tray originalSource
        Item.ConfirmDeleteSource itemId tray source ->
          update <| Item.Source itemId tray source
        Item.ConfirmDeleteLink itemId tray note _ _ ->
          update <| Item.Note itemId tray note
        Item.NewQuestion itemId tray question ->
          update <| Item.ConfirmDiscardNewQuestion itemId tray question
        Item.ConfirmDiscardNewQuestion itemId tray question ->
          update <| Item.ConfirmDiscardNewQuestion itemId tray question
        _ -> slipbox

    Submit ->
      case item of
        Item.ConfirmDeleteNote _ _ noteToDelete ->
          let
            links = List.filter (\l -> not <| isAssociated noteToDelete l ) content.links
            notesWithDeletedNoteRemoved = List.filter (isNotLambda Note.is noteToDelete) content.notes
            (state, notes) = simulation notesWithDeletedNoteRemoved links
          in
          Slipbox
            { content | notes = notes
            , links = links
            , items = List.map (deleteNoteItemStateChange noteToDelete) <| removeItemFromList item content.items
            , state = state
            }

        Item.ConfirmDeleteSource _ _ source ->
          Slipbox
            { content | sources = List.filter (isNotLambda Source.is source) content.sources
            , items = removeItemFromList item content.items
            }

        Item.NewNote itemId tray noteContent ->
          let
              (note, idGenerator) = Note.create content.idGenerator
                <| { content = noteContent.content, source = noteContent.source, variant = Note.Regular }
              (state, notes) = simulation (note :: content.notes) content.links
          in
          Slipbox
            { content | notes = notes
            , items = List.map (\i -> if Item.is item i then Item.Note itemId tray note else i) content.items
            , state = state
            , idGenerator = idGenerator
            }

        Item.NewSource itemId tray sourceContent ->
          let
              ( source, generator ) = Source.createSource content.idGenerator sourceContent
          in
          Slipbox
            { content | sources = source :: content.sources
            , items = List.map (\i -> if Item.is item i then Item.Source itemId tray source else i) content.items
            , idGenerator = generator
            }

        Item.EditingNote itemId tray originalNote editingNote ->
          let
              conditionallyUpdateTargetNoteWithEdits = updateLambda Note.is ( updateNoteEdits editingNote ) editingNote
          in
          Slipbox
            { content | notes = List.map conditionallyUpdateTargetNoteWithEdits content.notes
            , items = List.map (\i -> if Item.is item i then Item.Note itemId tray editingNote else i) content.items
            }

        Item.EditingSource itemId tray _ sourceWithEdits ->
          let
              conditionallyUpdateTargetSourceWithEdits = updateLambda Source.is ( updateSourceEdits sourceWithEdits ) sourceWithEdits
          in
          Slipbox
            { content | sources = List.map conditionallyUpdateTargetSourceWithEdits content.sources
            , items = List.map (\i -> if Item.is item i then Item.Source itemId tray sourceWithEdits else i) content.items
            }

        Item.AddingLinkToNoteForm itemId tray _ note maybeNoteToBeLinked ->
          case maybeNoteToBeLinked of
            Just noteToBeLinked ->
              let
                  (link, idGenerator) = Link.create content.idGenerator note noteToBeLinked
                  links = link :: content.links
                  (state, notes) = simulation content.notes links
              in
              Slipbox
                { content | notes = notes
                , links = links
                , items = List.map (\i -> if Item.is item i then Item.Note itemId tray note else i) content.items
                , state = state
                , idGenerator = idGenerator
                }
            _ -> slipbox

        Item.ConfirmDeleteLink itemId tray note _ link ->
          let
            trueIfNotTargetLink = isNotLambda Link.is link
            links = List.filter trueIfNotTargetLink content.links
            (state, notes) = simulation content.notes links
          in
          Slipbox
            { content | notes = notes
            , links = links
            , items = List.map (\i -> if Item.is item i then Item.Note itemId tray note else i) content.items
            , state = state
            }

        Item.ConfirmDiscardNewNoteForm _ _ _ ->
          Slipbox { content | items = removeItemFromList item content.items }

        Item.ConfirmDiscardNewSourceForm _ _ _ ->
          Slipbox { content | items = removeItemFromList item content.items }

        Item.NewQuestion itemId tray question ->
          let
              (note, idGenerator) = Note.create content.idGenerator
                <| { content = question, source = "n/a", variant = Note.Question }
              (state, notes) = simulation (note :: content.notes) content.links
          in
          Slipbox
            { content | notes = notes
            , items = List.map (\i -> if Item.is item i then Item.Note itemId tray note else i) content.items
            , state = state
            , idGenerator = idGenerator
            }

        Item.ConfirmDiscardNewQuestion _ _ _ ->
          Slipbox { content | items = removeItemFromList item content.items }

        _ -> slipbox

    OpenTray ->
      Slipbox { content | items = List.map ( updateLambda Item.is Item.openTray item ) content.items }

    CloseTray ->
      Slipbox { content | items = List.map ( updateLambda Item.is Item.closeTray item ) content.items }

updateLambda : ( a -> a -> Bool ) -> ( a -> a ) -> a -> ( a -> a )
updateLambda is update target =
  \maybeTarget ->
    if is target maybeTarget then
      update maybeTarget
    else
      maybeTarget

isNotLambda : ( a -> a -> Bool) -> a -> ( a -> Bool )
isNotLambda is target =
  \maybeTarget ->
    if is target maybeTarget then
      False
    else
      True

tick : Slipbox -> Slipbox
tick slipbox =
  let
    content = getContent slipbox
    ( state, notes ) = tick_ content.notes content.state
  in
  Slipbox { content | notes = notes, state = state }

simulationIsCompleted : Slipbox -> Bool
simulationIsCompleted slipbox =
  let
    content = getContent slipbox
    thereAreNoNotes = ( List.length <| content.notes ) == 0
  in
  if thereAreNoNotes then
    True
  else
    extract content.state |> Force.isCompleted

decode : Json.Decode.Decoder Slipbox
decode =
  Json.Decode.map4
    slipbox_
    ( Json.Decode.field "notes" (Json.Decode.list Note.decode) )
    ( Json.Decode.field "links" (Json.Decode.list Link.decode) )
    ( Json.Decode.field "sources" (Json.Decode.list Source.decode) )
    ( Json.Decode.field "idGenerator" IdGenerator.decode )

encode : Slipbox -> String
encode slipbox =
  let
    info = getContent slipbox
  in
  Json.Encode.encode 0
    <| Json.Encode.object
      [ ( "notes", Json.Encode.list Note.encode info.notes )
      , ( "links", Json.Encode.list Link.encode info.links )
      , ( "sources", Json.Encode.list Source.encode info.sources )
      , ( "idGenerator", IdGenerator.encode info.idGenerator )
      ]

-- Helper Functions
slipbox_: ( List Note.Note ) -> ( List Link.Link ) -> ( List Source.Source ) -> IdGenerator.IdGenerator -> Slipbox
slipbox_ notesBeforeSimulation links sources idGenerator =
  let
    ( state, notes ) = simulation notesBeforeSimulation links
  in
  Slipbox <| Content notes links [] sources state idGenerator

buildItemList : Item.Item -> Item.Item -> (Item.Item -> (List Item.Item) -> (List Item.Item))
buildItemList itemToMatch itemToAdd =
  \item list -> if Item.is item itemToMatch then item :: (itemToAdd :: list) else item :: list

deleteNoteItemStateChange : Note.Note -> Item.Item -> Item.Item
deleteNoteItemStateChange deletedNote item =
  case item of
    Item.AddingLinkToNoteForm itemId tray search note maybeNoteToBeLinked ->
      case maybeNoteToBeLinked of
        Just noteToBeLinked -> 
          if Note.is noteToBeLinked deletedNote then
            Item.AddingLinkToNoteForm itemId tray search note Nothing
          else 
            item
        _ -> item   
    _ -> item

conditionalUpdate : a -> (a -> Bool) -> (a -> a)
conditionalUpdate updatedItem itemIdentifier =
  (\i -> if itemIdentifier i then updatedItem else i)

updateNoteEdits : Note.Note -> Note.Note -> Note.Note
updateNoteEdits noteWithEdits originalNote =
  let
      updatedContent = Note.getContent noteWithEdits
      updatedSource = Note.getSource noteWithEdits
      updatedVariant = Note.getVariant noteWithEdits
  in
  Note.updateContent updatedContent
    <| Note.updateSource updatedSource
      <| Note.updateVariant updatedVariant originalNote

updateSourceEdits : Source.Source -> Source.Source -> Source.Source
updateSourceEdits sourceWithEdits originalSource =
  let
      updatedTitle = Source.getTitle sourceWithEdits
      updatedAuthor = Source.getAuthor sourceWithEdits
      updatedContent = Source.getContent sourceWithEdits
  in
  Source.updateTitle updatedTitle
    <| Source.updateAuthor updatedAuthor
      <| Source.updateContent updatedContent originalSource

linkIsRelevant : ( List Note.Note ) -> Link.Link -> Bool
linkIsRelevant notes link =
  let
    sourceInNotes = getSource link notes /= Nothing
    targetInNotes = getTarget link notes /= Nothing
  in
  sourceInNotes && targetInNotes

tryFindItemFromComponent : ( List Item.Item ) -> ( Item.Item -> (Bool) ) -> ( Maybe Item.Item )
tryFindItemFromComponent items filterCondition =
  List.head <| List.filter filterCondition items

hasNote : Note.Note -> Item.Item -> Bool
hasNote note item =
  case Item.getNote item of
    Just noteOnItem -> Note.is note noteOnItem
    Nothing -> False

hasSource : Source.Source -> Item.Item -> Bool
hasSource source item =
  case Item.getSource item of
    Just sourceOnItem -> Source.is source sourceOnItem
    Nothing -> False

isAssociated : Note.Note -> Link.Link -> Bool
isAssociated note link =
  Link.isSource link note || Link.isTarget link note

getSource : Link.Link -> (List Note.Note) -> (Maybe Note.Note)
getSource link notes =
  List.head <| List.filter (Link.isSource link) notes

getTarget : Link.Link -> (List Note.Note) -> (Maybe Note.Note)
getTarget link notes =
  List.head <| List.filter (Link.isTarget link) notes

-- SIMULATION

type alias SimulationRecord =
  { id: Int
  , x: Float
  , y: Float
  , vx: Float
  , vy: Float
  }

type State comparable = State (Force.State comparable)

-- EXPOSED

initNote : Int -> SimulationRecord
initNote id =
  let
    entity = Force.entity id 1
  in
    SimulationRecord id entity.x entity.y entity.vx entity.vy

simulation : ( List Note.Note ) -> ( List Link.Link ) -> ( State Int, (List Note.Note) )
simulation notes links =
  let
    entities = List.map toEntity notes
    state = stateBuilder entities links
  in
  Force.tick state entities |> toStateRecordTuple

tick_ : ( List Note.Note ) -> State Int -> ( State Int, (List Note.Note) )
tick_ notes state =
  let
    entities = List.map toEntity notes
  in
   Force.tick (extract state) entities |> toStateRecordTuple


-- HELPERS

stateBuilder : ( List (Force.Entity Int { note : Note.Note })) -> ( List Link.Link ) -> Force.State Int
stateBuilder entities links =
  Force.simulation
        [ Force.manyBodyStrength -15 (List.map (\n -> n.id) entities)
        , Force.links <| List.map (\link -> ( Link.getSourceId link, Link.getTargetId link)) links
        , Force.center 0 0
        ]

toEntity : Note.Note -> (Force.Entity Int { note : Note.Note })
toEntity note =
  { id = Note.getId note, x = Note.getX note, y = Note.getY note, vx = Note.getVx note, vy = Note.getVy note, note = note }

updateNote: (Force.Entity Int { note : Note.Note }) -> Note.Note
updateNote entity =
  Note.updateX entity.x <| Note.updateY entity.y <| Note.updateVx entity.vx <| Note.updateVy entity.vy entity.note

extract : State Int -> Force.State Int
extract state =
  case state of
     State simState -> simState

toStateRecordTuple : ( Force.State Int, List ( Force.Entity Int { note : Note.Note } ) ) -> ( State Int, (List Note.Note) )
toStateRecordTuple ( simState, records ) =
  ( State simState
  , List.map updateNote records
  )