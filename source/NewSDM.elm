module NewSDM exposing (Model, page, init, initCmd, update, Msg, subscriptions)

import Constants exposing (apiRoot)
import List.Extra exposing (elemIndex)
import Html exposing (Html)
import Http
import Material
import Material.Options as Options
import Material.List as Lists
import Material.Icon as Icon
import Material.Typography as Typo
import Material.Button as Button
import Material.Helpers exposing (lift)
import Material.Spinner as Loading
import ScenariosView as Scns
import AlgorithmsView as Algs
import OccurrenceSetsView as Occs
import Page exposing (Page)
import ScenariosList as SL
import Helpers exposing (undefined, unsafeFromMaybe)
import Decoder
import Encoder


-- MODEL


type Tab
    = Algorithms
    | OccurrenceSets
    | ModelScenario
    | ProjScenarios
    | PostProjection


tabs : List Tab
tabs =
    [ OccurrenceSets, Algorithms, ModelScenario, ProjScenarios, PostProjection ]


tabIndex : Tab -> Int
tabIndex tab =
    elemIndex tab tabs |> Maybe.withDefault 0


type WorkFlowState
    = Defining
    | Submitting
    | Submitted
    | SubmissionFailed


type alias Model =
    { mdl : Material.Model
    , selectedTab : Tab
    , modelScenario : Scns.Model
    , projectionScenarios : Scns.Model
    , algorithmsModel : Algs.Model
    , occurrenceSets : Occs.Model
    , availableScenarios : SL.Model
    , workFlowState : WorkFlowState
    }


toApi : Model -> Decoder.ProjectionPOST
toApi { algorithmsModel, occurrenceSets, modelScenario, projectionScenarios } =
    Decoder.ProjectionPOST
        { algorithms = Algs.toApi algorithmsModel
        , occurrenceSets = Occs.toApi occurrenceSets
        , modelScenario =
            Scns.toApi Decoder.ProjectionPOSTModelScenario modelScenario
                |> List.head
                |> unsafeFromMaybe "No Model Scenario Selected"
        , projectionScenarios =
            Scns.toApi Decoder.ProjectionPOSTProjectionScenariosItem projectionScenarios
                |> Decoder.ProjectionPOSTProjectionScenarios
        }


submitJob : Model -> Cmd Msg
submitJob model =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Accept" "application/json", Http.header "Content-Type" "text/plain" ]
        , url = apiRoot ++ "sdmProject"
        , body = Http.jsonBody <| Encoder.encodeProjectionPOST <| toApi model
        , expect = Http.expectString
        , timeout = Nothing
        , withCredentials = False
        }
        |> Http.send JobSubmitted


init : Model
init =
    { mdl = Material.model
    , selectedTab = OccurrenceSets
    , modelScenario = Scns.init Scns.ModelScenario
    , projectionScenarios = Scns.init Scns.ProjectionScenarios
    , algorithmsModel = Algs.init
    , occurrenceSets = Occs.init
    , availableScenarios = SL.init
    , workFlowState = Defining
    }


type Msg
    = Mdl (Material.Msg Msg)
    | SelectTab Tab
    | SubmitJob
    | JobSubmitted (Result Http.Error String)
    | Restart
    | ProjScnsMsg Scns.Msg
    | MdlScnMsg Scns.Msg
    | AlgsMsg Algs.Msg
    | OccsMsg Occs.Msg
    | SLMsg SL.Msg


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectTab tab ->
            ( { model | selectedTab = tab }, Cmd.none )

        SubmitJob ->
            ( { model | workFlowState = Submitting }, submitJob model )

        JobSubmitted (Ok result) ->
            Debug.log "submitted" (toString result)
                |> always ( { model | workFlowState = Submitted }, Cmd.none )

        JobSubmitted (Err err) ->
            Debug.log "submission failed" (toString err)
                |> always ( { model | workFlowState = SubmissionFailed }, Cmd.none )

        Restart ->
            ( { init | availableScenarios = model.availableScenarios }, Cmd.none )

        ProjScnsMsg msg_ ->
            lift
                .projectionScenarios
                (\m x -> { m | projectionScenarios = x })
                ProjScnsMsg
                Scns.update
                msg_
                model

        MdlScnMsg msg_ ->
            lift
                .modelScenario
                (\m x -> { m | modelScenario = x })
                MdlScnMsg
                Scns.update
                msg_
                model

        AlgsMsg msg_ ->
            lift
                .algorithmsModel
                (\m x -> { m | algorithmsModel = x })
                AlgsMsg
                Algs.update
                msg_
                model

        OccsMsg msg_ ->
            lift
                .occurrenceSets
                (\m x -> { m | occurrenceSets = x })
                OccsMsg
                Occs.update
                msg_
                model

        SLMsg msg_ ->
            lift
                .availableScenarios
                (\m x -> { m | availableScenarios = x })
                SLMsg
                SL.update
                msg_
                model

        Mdl msg_ ->
            Material.update Mdl msg_ model


tabTitle : Tab -> Html msg
tabTitle tab =
    Html.text <|
        case tab of
            Algorithms ->
                "Algorithms"

            OccurrenceSets ->
                "Species Data"

            ModelScenario ->
                "Model Input Layers"

            ProjScenarios ->
                "Projection Input Layers"

            PostProjection ->
                "Submit Project"


mainView : Model -> Html Msg
mainView model =
    case model.workFlowState of
        Submitted ->
            Options.div [ Options.css "text-align" "center", Options.css "padding-top" "50px", Typo.headline ]
                [ Html.text "Job was successfully submitted."
                , Html.p []
                    [ Button.render Mdl
                        [ 0 ]
                        model.mdl
                        [ Button.raised, Options.onClick Restart ]
                        [ Html.text "OK" ]
                    ]
                ]

        SubmissionFailed ->
            Options.div [ Options.css "text-align" "center", Options.css "padding-top" "50px", Typo.headline ]
                [ Html.text "There was a problem submitting the job."
                , Html.p []
                    [ Button.render Mdl
                        [ 0 ]
                        model.mdl
                        [ Button.raised, Options.onClick SubmitJob ]
                        [ Html.text "Retry" ]
                    ]
                ]

        Submitting ->
            Options.div [ Options.css "text-align" "center", Options.css "padding-top" "50px", Typo.headline ]
                [ Html.text "Submitting job..."
                , Html.p [] [ Loading.spinner [ Loading.active True ] ]
                ]

        Defining ->
            case model.selectedTab of
                Algorithms ->
                    model.algorithmsModel |> Algs.view [] |> Html.map AlgsMsg

                OccurrenceSets ->
                    model.occurrenceSets |> Occs.view [] |> Html.map OccsMsg

                ModelScenario ->
                    model.modelScenario |> Scns.view [ 0 ] model.availableScenarios |> Html.map MdlScnMsg

                ProjScenarios ->
                    model.projectionScenarios |> Scns.view [ 0 ] model.availableScenarios |> Html.map ProjScnsMsg

                PostProjection ->
                    Options.div [ Options.css "padding" "20px" ]
                        [ Html.p []
                            [ Html.text """
                                 Once all of the inputs below have been defined the job
                                 can be submitted.
                                 """
                            ]
                        , Lists.ul [] <| List.map (taskLI model) tasks
                        , Button.render Mdl
                            [ 0 ]
                            model.mdl
                            [ Button.raised
                            , Button.disabled |> Options.when (not <| complete model)
                            , Options.onClick SubmitJob |> Options.when (complete model)
                            ]
                            [ Html.text "Submit Job" ]
                          -- , Button.render Mdl
                          --     [ 1 ]
                          --     model.mdl
                          --     [ Button.raised
                          --     , Options.onClick Restart
                          --     , Options.css "margin-left" "40px"
                          --     ]
                          --     [ Html.text "Start Over" ]
                        ]


taskLI : Model -> ( Tab, Model -> Bool ) -> Html Msg
taskLI model ( tab, complete ) =
    let
        icon =
            if complete model then
                Icon.i "check_box"
            else
                Icon.i "check_box_outline_blank"
    in
        Lists.li [] [ Lists.content [] [ icon, tabTitle tab ] ]


tasks : List ( Tab, Model -> Bool )
tasks =
    [ ( Algorithms, (.algorithmsModel >> Algs.complete) )
    , ( OccurrenceSets, (.occurrenceSets >> Occs.complete) )
    , ( ModelScenario, (.modelScenario >> Scns.complete) )
    , ( ProjScenarios, (.projectionScenarios >> Scns.complete) )
    ]


complete : Model -> Bool
complete model =
    List.all (\( _, taskComplete ) -> taskComplete model) tasks


selectedTab : Model -> Int
selectedTab model =
    tabIndex model.selectedTab


selectTab : Int -> Msg
selectTab i =
    List.drop i tabs |> List.head |> Maybe.withDefault Algorithms |> SelectTab


tabTitles : Model -> List (Html msg)
tabTitles model =
    List.map tabTitle tabs


page : Page Model Msg
page =
    { view = mainView
    , selectedTab = selectedTab
    , selectTab = selectTab
    , tabTitles = tabTitles
    }


initCmd : (Msg -> msg) -> Cmd msg
initCmd map =
    SL.getScenarios SLMsg |> Cmd.map map


subscriptions : (Msg -> msg) -> Sub msg
subscriptions liftMsg =
    Sub.batch
        [ Occs.subscriptions (OccsMsg >> liftMsg)
        , Scns.subscriptions (MdlScnMsg >> liftMsg)
        , Scns.subscriptions (ProjScnsMsg >> liftMsg)
        ]