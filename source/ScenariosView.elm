module ScenariosView
    exposing
        ( Model
        , Msg
        , init
        , update
        , view
        , toApi
        , problems
        , subscriptions
        )

import List.Extra exposing (remove)
import Maybe.Extra as Maybe exposing ((?))
import Decoder
    exposing
        ( AtomObjectRecord
        , AtomList(..)
        , decodeAtomList
        , AtomObject(..)
        , decodeScenario
        , Scenario(..)
        , ScenarioRecord
        , ScenarioPackageRecord
        , ScenarioPackageScenarios(..)
        , ScenarioMetadata(..)
        , MapLayers(..)
        , MapLayersItem(..)
        , BoomPOSTModelScenario(..)
        , BoomPOSTProjectionScenarios(..)
        , BoomPOSTProjectionScenariosItem(..)
        )
import Material
import Material.List as L
import Material.Grid as Grid
import Material.Card as Card
import Material.Elevation as Elevation
import Material.Options as Options
import Material.Typography as Typo
import Material.Toggles as Toggles
import Html exposing (Html)
import Helpers exposing (Index, undefined)
import ScenariosList as SL


type alias Model =
    { mdl : Material.Model
    , package : Maybe ScenarioPackageRecord
    , projectionScenarios : List ScenarioRecord
    , modelScenario : Maybe ScenarioRecord
    }


type alias BoomPOSTScenarios =
    { modelScenario : BoomPOSTModelScenario, projectionScenarios : BoomPOSTProjectionScenarios }


toApi : Model -> Result String BoomPOSTScenarios
toApi { modelScenario, projectionScenarios } =
    Result.map2 BoomPOSTScenarios
        (modelScenario
            |> Maybe.map (\s -> BoomPOSTModelScenario { scenarioId = Just s.id, scenarioCode = s.code })
            |> Result.fromMaybe "No Model Scenario Selected"
        )
        (projectionScenarios
            |> List.map (\s -> BoomPOSTProjectionScenariosItem { scenarioId = Just s.id, scenarioCode = s.code })
            |> BoomPOSTProjectionScenarios
            |> Ok
        )


type Msg
    = Mdl (Material.Msg Msg)
    | SelectModelScenario ScenarioPackageRecord ScenarioRecord
    | SelectProjectionScenario ScenarioPackageRecord ScenarioRecord
    | UnselectProjectionScenario ScenarioRecord


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Mdl msg_ ->
            Material.update Mdl msg_ model

        SelectModelScenario p s ->
            if Just p == model.package then
                { model | modelScenario = Just s } ! []
            else
                { model | modelScenario = Just s, projectionScenarios = [], package = Just p } ! []

        SelectProjectionScenario p s ->
            if Just p == model.package then
                { model | projectionScenarios = (s :: model.projectionScenarios) } ! []
            else
                { model | projectionScenarios = [ s ], modelScenario = Nothing, package = Just p } ! []

        UnselectProjectionScenario id ->
            ( { model | projectionScenarios = remove id model.projectionScenarios }, Cmd.none )


type alias ScenarioLiFunc =
    Int -> Scenario -> Html Msg


scenarioTitle : Scenario -> String
scenarioTitle (Scenario scenario) =
    Maybe.or
        (scenario.metadata |> Maybe.andThen (\(ScenarioMetadata md) -> md.title))
        scenario.code
        |> Maybe.withDefault (toString scenario.id)


listScenarios : ScenarioLiFunc -> ScenarioPackageScenarios -> Html Msg
listScenarios liFunc (ScenarioPackageScenarios scenarios) =
    scenarios
        |> List.sortBy scenarioTitle
        |> List.indexedMap liFunc
        |> L.ul []


modelScenarioLI : Index -> Model -> ScenarioPackageRecord -> Maybe ScenarioRecord -> ScenarioLiFunc
modelScenarioLI index model package currentlySelected i (Scenario s) =
    let
        isSelected =
            Just s == currentlySelected

        onToggle =
            if isSelected then
                Options.nop
            else
                Options.onToggle (SelectModelScenario package s)
    in
        L.li []
            [ L.content [] [ Html.text <| scenarioTitle (Scenario s) ]
            , L.content2 []
                [ Toggles.radio Mdl
                    (i :: index)
                    model.mdl
                    [ Toggles.value isSelected
                    , Toggles.group (toString index)
                    , onToggle
                    ]
                    []
                ]
            ]


projectionScenarioLI : Index -> Model -> ScenarioPackageRecord -> List ScenarioRecord -> ScenarioLiFunc
projectionScenarioLI index model package currentlySelected i (Scenario s) =
    let
        isSelected =
            List.member s currentlySelected

        toggle =
            if isSelected then
                UnselectProjectionScenario s
            else
                SelectProjectionScenario package s
    in
        L.li []
            [ L.content [] [ Html.text <| scenarioTitle (Scenario s) ]
            , L.content2 []
                [ Toggles.checkbox Mdl
                    (i :: index)
                    model.mdl
                    [ Toggles.value isSelected
                    , Options.onToggle toggle
                    ]
                    []
                ]
            ]


observedFilter : ScenarioPackageScenarios -> ScenarioPackageScenarios
observedFilter (ScenarioPackageScenarios scenarios) =
    scenarios
        |> List.filter (\(Scenario s) -> Maybe.map (String.startsWith "observed") s.code ? False)
        |> ScenarioPackageScenarios


packageCard : Index -> Model -> ScenarioPackageRecord -> Html Msg
packageCard index model package =
    let
        isSelected =
            model.package == Just package

        modelLI =
            if isSelected then
                modelScenarioLI (0 :: index) model package model.modelScenario
            else
                modelScenarioLI (0 :: index) model package Nothing

        projLI =
            if isSelected then
                projectionScenarioLI (1 :: index) model package model.projectionScenarios
            else
                projectionScenarioLI (1 :: index) model package []
    in
        Card.view
            [ Options.css "width" "100%"
            , if isSelected then
                Elevation.e8
              else
                Elevation.e2
            ]
            [ Card.title [ Card.border ] [ Card.head [] [ Html.text <| "Package: " ++ (package.name ? "") ] ]
            , Card.text []
                [ Options.div [ Typo.subhead ] [ Html.text "Choose Model Layers" ]
                , listScenarios modelLI (observedFilter package.scenarios)
                , Options.div [ Typo.subhead ] [ Html.text "Choose Projection Layers" ]
                , listScenarios projLI package.scenarios
                ]
            ]


view : Index -> SL.Model -> Model -> Html Msg
view index sl model =
    sl.packages
        |> List.indexedMap (\i package -> Grid.cell [ Grid.size Grid.All 4 ] [ packageCard (i :: index) model package ])
        |> Grid.grid []


problems : Model -> Maybe String
problems model =
    case model.projectionScenarios of
        [] ->
            Just "No scenarios selected."

        _ ->
            Nothing


init : Model
init =
    { mdl = Material.model
    , package = Nothing
    , modelScenario = Nothing
    , projectionScenarios = []
    }


subscriptions : (Msg -> msg) -> Sub msg
subscriptions liftMsg =
    Sub.none
