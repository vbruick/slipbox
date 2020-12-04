module Note exposing 
  ( Note, getId
  , getX, getY
  , getVariant, getGraphState
  , getContent, getTransform
  , contains, isLinked
  , isLinked, canLink
  , isAssociated, is
  , compress, expand
  , note, updateContent
  , updateSource, updateVariant
  , GraphState, Variant
  )
import IdGenerator
import IdGenerator exposing (IdGenerator)

type Note = Note Info
getInfo : Note -> Info 
getInfo note =
  case note of Note content -> content
type alias Info =
  { id : NoteId
  , content : String
  , source : String
  , variant : Variant
  , graphState : GraphState
  , x : Float
  , y : Float
  , vx : Float
  , vy : Float
  }
type alias NoteId = Int
type Variant = Regular | Index
type GraphState = Compressed | Expanded
type alias NoteRecord = 
  { content : String
  , source : String
  , noteType: String
  }

getId : Note -> NoteId
getId note =
  id <| getInfo note

getX : Note -> Float
getX note =
  x <| getInfo note
getY : Note -> Float
getY note =
  y <| getInfo note
  
getVariant : Note -> Variant
getVariant note =
  variant <| getInfo note

getGraphState : Note -> GraphState
getGraphState note =
  graphState <| getInfo note

getContent : Note -> String
getContent note =
  content <| getInfo note

getTransform : Note -> String
getTransform note =
  let
      info = getInfo note
      x = String.fromFloat info.x
      y = String.fromFloat info.y
  in
  String.concat [ "translate(", x, " ", y, ")" ]

getSource : Note -> String
getSource note =
  source <| getInfo note

contains : String -> Note -> Bool
contains string note =
  let
      info = getInfo note
      contains = \s -> String.contains (String.toLower string) <| String.toLower s
  in
  contains info.content || contains info.source
  
isLinked : (List Link.Link) -> Note -> Note -> Bool
isLinked links note1 note2 =
  linkBelongsToNotes note1 note2 |> List.any links

canLink : (List Link.Link) -> Note -> Note -> Bool
canLink links note1 note2 =
  not <| isLinked note1 note2
  && ( getVariant note1 == Regular || getVariant note2 == Regular )

isAssociated : Source.Source -> Note -> Bool
isAssociated source note =
  Source.getTitle source == Note.getSource note

is : Note -> Note -> Bool
is note1 note2 =
  (getId note1) == (getId note2)

compress : Note -> Note
compress note =
  let
      info = getInfo note
  in
  Note { info | graphState = Compressed }

expand : Note -> Note
expand note =
  let
      info = getInfo note
  in
  Note { info | graphState = Expanded }

create : IdGenerator.IdGenerator -> NoteRecord -> ( Note, IdGenerator.IdGenerator)
create generator record =
  let
      (id, idGenerator) = IdGenerator.generateId generator
  in
  
  ( Note <| Info
    id
    record.content
    record.source
    record.variant
    Compressed
    0 0 0 0
  , idGenerator
  )

updateContent : String -> Note -> Note
updateContent content =
  let
      info = getInfo note
  in
  Note { info | content = content }

updateSource : String -> Note -> Note
updateSource source =
  let
      info = getInfo note
  in
  Note { info | source = source }

updateVariant : Variant -> Note -> Note
updateVariant variant =
  let
      info = getInfo note
  in
  Note { info | variant = variant }

-- TODO
-- init: NoteRecord -> Note
-- init record =
--   toNote (Simulation.init record.id) record

-- TODO
-- update: Simulation.SimulationRecord -> Note -> Note
-- update simRecord note =
--   case note of
--     Note content -> Note {content | x = simRecord.x , y = simRecord.y, vx = simRecord.vx, vy = simRecord.vy}
--     Selected content sContent -> Selected {content | x = simRecord.x , y = simRecord.y, vx = simRecord.vx, vy = simRecord.vy} sContent

-- Exposed Functions
-- sortDesc: (Note -> Note -> Order)
-- sortDesc noteA noteB =
--   case compare (getId noteA) (getId noteB) of
--        LT -> GT
--        EQ -> EQ
--        GT -> LT

-- Helper
linkBelongsToNotes : Note -> Note -> Link.Link -> Bool
linkBelongsToNotes note1 note2 link=
  let
      linkSourceId = Link.getSourceId link
      linkTargetId = Link.getTargetId link
      note1Id = getId note1
      note2Id = getId note2
  in
  (linkSourceId == note1Id && linkTargetId == note2Id)
  || (linkSourceId == note2Id && linkTargetId == note1Id)