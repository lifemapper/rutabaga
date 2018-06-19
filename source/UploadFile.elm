{-
   Copyright (C) 2018, University of Kansas Center for Research

   Lifemapper Project, lifemapper [at] ku [dot] edu,
   Biodiversity Institute,
   1345 Jayhawk Boulevard, Lawrence, Kansas, 66045, USA

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or (at
   your option) any later version.

   This program is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
   02110-1301, USA.
-}


port module UploadFile exposing (Model, Msg, init, update, view, subscriptions)

import Html exposing (Html)
import Html.Attributes as Attribute
import Html.Events as Events
import ProgramFlags exposing (Flags)
import Material
import Material.Textfield as Textfield
import Material.Progress as Progress
import Material.Options as Options
import Material.Button as Button
import Json.Decode as Decode
import Helpers exposing (Index)


port fileSelected : String -> Cmd msg


port uploadProgress : ({ id : String, loaded : Int, total : Int } -> msg) -> Sub msg


port uploadComplete : ({ id : String, response : String, status : Int } -> msg) -> Sub msg


port uploadFailed : ({ id : String, response : String } -> msg) -> Sub msg


port uploadCanceled : (String -> msg) -> Sub msg


port uploadCmd : { id : String, url : String } -> Cmd msg


port selectedFileName : ({ id : String, filename : String } -> msg) -> Sub msg


type UploadStatus
    = StartingUpload
    | Uploading ( Int, Int )
    | UploadComplete Int String
    | UploadFailed String
    | UploadCanceled


type FileSelectState
    = FileNotSelected
    | FileSelected
    | GotFileName { localFileName : String, uploadAs : String }
    | UploadingFile { localFileName : String, uploadAs : String, status : UploadStatus }
    | FileNameConflict { localFileName : String, uploadAs : String }


type alias Model =
    FileSelectState


init : Model
init =
    FileNotSelected


type UploadMsg
    = FileSelectedMsg String
    | GotFileNameMsg { id : String, filename : String }
    | GotUploadStatus { id : String, status : UploadStatus }
    | UpdateUploadFilename String
    | DoUpload


type alias Msg =
    UploadMsg


fileSelectId : Index -> String
fileSelectId index =
    "file-select" ++ (index |> List.map toString |> String.join "-" )


update : Index -> Flags -> UploadMsg -> FileSelectState -> ( FileSelectState, Cmd msg )
update index flags msg state =
    case msg of
        FileSelectedMsg id ->
            ( FileSelected, fileSelected id )

        GotFileNameMsg { id, filename } ->
            if id == fileSelectId index then
                ( GotFileName { localFileName = filename, uploadAs = filename }, Cmd.none )
            else
                ( state, Cmd.none )

        UpdateUploadFilename uploadAs ->
            case state of
                GotFileName info ->
                    ( GotFileName { info | uploadAs = uploadAs }, Cmd.none )

                FileNameConflict info ->
                    ( FileNameConflict { info | uploadAs = uploadAs }, Cmd.none )

                _ ->
                    ( state, Cmd.none )

        DoUpload ->
            case state of
                GotFileName info ->
                    doUpload index flags info

                FileNameConflict info ->
                    doUpload index flags info

                _ ->
                    ( state, Cmd.none )

        GotUploadStatus { id, status } ->
            if id == fileSelectId index then
                case state of
                    UploadingFile ({ localFileName, uploadAs } as info) ->
                        case status of
                            UploadComplete 409 _ ->
                                ( FileNameConflict
                                    { localFileName = localFileName
                                    , uploadAs = uploadAs
                                    }
                                , Cmd.none
                                )

                            _ ->
                                ( UploadingFile { info | status = status }, Cmd.none )

                    _ ->
                        ( state, Cmd.none )
            else
                ( state, Cmd.none )


doUpload : Index -> Flags -> { localFileName : String, uploadAs : String } -> ( FileSelectState, Cmd msg )
doUpload index flags { localFileName, uploadAs } =
    let
        url =
            flags.apiRoot ++ "upload?uploadType=tree&fileName=" ++ uploadAs
    in
        ( UploadingFile
            { localFileName = localFileName
            , uploadAs = uploadAs
            , status = StartingUpload
            }
        , uploadCmd { id = fileSelectId index, url = url }
        )


view : (Material.Msg msg -> msg) -> (UploadMsg -> msg) -> Index -> Material.Model -> FileSelectState -> List (Html msg)
view mapMdlMsg mapMsg index mdl state =
    case state of
        FileNameConflict { localFileName, uploadAs } ->
            [ Html.p [] [ Html.text ("File selected: " ++ localFileName) ]
            , Html.p [] [ Html.text "Filename already in use. Choose another." ]
            , Html.p []
                [ Textfield.render mapMdlMsg
                    (0 :: index)
                    mdl
                    [ Textfield.label "Upload as"
                    , Textfield.floatingLabel
                    , Textfield.value uploadAs
                    , Options.onInput (UpdateUploadFilename >> mapMsg)
                    ]
                    []
                , Button.render mapMdlMsg
                    (1 :: index)
                    mdl
                    [ Button.raised, Options.onClick (mapMsg DoUpload) ]
                    [ Html.text "Upload" ]
                ]
            ]

        UploadingFile { localFileName, uploadAs, status } ->
            case status of
                StartingUpload ->
                    [ Html.text <| "Starting upload of " ++ uploadAs ++ "..."
                    , Progress.indeterminate
                    ]

                Uploading ( loaded, total ) ->
                    [ Html.text <| "Uploading " ++ uploadAs ++ "..."
                    , Progress.progress (toFloat loaded / toFloat total * 100)
                    ]

                UploadComplete status response ->
                    [ Html.text <| "Finished uploading " ++ uploadAs ++ "." ]

                UploadFailed response ->
                    [ Html.text <| "Failed uploading " ++ uploadAs ++ "." ]

                UploadCanceled ->
                    [ Html.text <| "Failed uploading " ++ uploadAs ++ "." ]

        GotFileName { localFileName, uploadAs } ->
            [ Html.p [] [ Html.text ("File selected: " ++ localFileName) ]
            , Html.p []
                [ Textfield.render mapMdlMsg
                    (0 :: index)
                    mdl
                    [ Textfield.label "Upload as"
                    , Textfield.floatingLabel
                    , Textfield.value uploadAs
                    , Options.onInput (UpdateUploadFilename >> mapMsg)
                    ]
                    []
                , Button.render mapMdlMsg
                    (1 :: index)
                    mdl
                    [ Button.raised, Options.onClick (mapMsg DoUpload) ]
                    [ Html.text "Upload" ]
                ]
            ]

        FileSelected ->
            [ Html.text "Opening file..." ]

        FileNotSelected ->
            [ Html.input
                [ Attribute.type_ "file"
                , Attribute.id <| fileSelectId index
                , Events.on "change" (Decode.succeed <| mapMsg <| FileSelectedMsg <| fileSelectId index)
                ]
                []
            ]


subscriptions : (UploadMsg -> msg) -> Sub msg
subscriptions mapMsg =
    Sub.batch
        [ selectedFileName (GotFileNameMsg >> mapMsg)
        , uploadProgress
            (\{ id, total, loaded } ->
                GotUploadStatus { id = id, status = Uploading ( loaded, total ) } |> mapMsg
            )
        , uploadComplete
            (\{ id, response, status } ->
                GotUploadStatus { id = id, status = UploadComplete status response } |> mapMsg
            )
        , uploadFailed
            (\{ id, response } ->
                GotUploadStatus { id = id, status = UploadFailed response } |> mapMsg
            )
        , uploadCanceled
            (\id ->
                GotUploadStatus { id = id, status = UploadCanceled } |> mapMsg
            )
        ]
