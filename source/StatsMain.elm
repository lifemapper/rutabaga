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


port module StatsMain exposing (..)

import List.Extra as List
import Maybe.Extra as Maybe
import Set exposing (Set)
import Dict exposing (Dict)
import Html
import Html.Attributes
import Html.Events
import Svg exposing (..)
import Svg.Attributes exposing (..)
import Helpers exposing (formatNumber)


type alias StatsForSite =
    { id : Int
    , stats : List ( String, Maybe Float )
    }


port requestStats : () -> Cmd msg


port statsForSites :
    ({ sitesObserved : List StatsForSite
     , statNameLookup : List ( String, { name : String, description : String } )
     }
     -> msg
    )
    -> Sub msg


type alias DataScale =
    { minX : Float
    , minY : Float
    , maxX : Float
    , maxY : Float
    }


computeScale : List Record -> DataScale
computeScale data =
    { minX =
        Maybe.withDefault 0 <| agg Basics.min <| List.map .x data
    , maxX =
        Maybe.withDefault 0 <| agg Basics.max <| List.map .x data
    , minY =
        Maybe.withDefault 0 <| agg Basics.min <| List.map .y data
    , maxY =
        Maybe.withDefault 0 <| agg Basics.max <| List.map .y data
    }


type alias Point =
    { x : Float
    , y : Float
    }


type PixelPoint
    = PixelPoint Point


type SvgPoint
    = SvgPoint Point


type DataPoint
    = DataPoint Point


data2svg : DataScale -> DataPoint -> SvgPoint
data2svg ds (DataPoint { x, y }) =
    SvgPoint { x = 1000 * (x - ds.minX) / (ds.maxX - ds.minX), y = 1000 * (1 - (y - ds.minY) / (ds.maxY - ds.minY)) }


svg2data : DataScale -> SvgPoint -> DataPoint
svg2data ds (SvgPoint { x, y }) =
    DataPoint { x = x / 1000 * (ds.maxX - ds.minX) + ds.minX, y = (1 - y / 1000) * (ds.maxY - ds.minY) + ds.minY }


type alias SvgViewBox =
    { width : Float
    , height : Float
    , minX : Float
    , minY : Float
    , maxX : Float
    , maxY : Float
    }


svgViewBox : SvgViewBox
svgViewBox =
    { width = 500
    , height = 500
    , minX = -100
    , minY = 0
    , maxX = 1020
    , maxY = 1020
    }


pixel2svg : SvgViewBox -> PixelPoint -> SvgPoint
pixel2svg { width, height, minX, minY, maxX, maxY } (PixelPoint { x, y }) =
    SvgPoint { x = x / width * (maxX - minX) + minX, y = y / height * (maxY - minY) + minY }


inViewBox : SvgViewBox -> SvgPoint -> Bool
inViewBox { width, height, minX, minY, maxX, maxY } (SvgPoint { x, y }) =
    minX <= x && maxX >= x && minY <= y && maxY >= y


type alias MouseEvent =
    { eventType : String
    , x : Float
    , y : Float
    , ctrlKey : Bool
    }


port mouseEvent : (MouseEvent -> msg) -> Sub msg


port sitesSelected : (List Int -> msg) -> Sub msg


type alias Model =
    { selected : Set Int
    , flagged : Dict Int String
    , selecting : Maybe ( SvgPoint, SvgPoint )
    , variables : List String
    , statNames : Dict String { name : String, description : String }
    , stats : List StatsForSite
    , displayedRecords : List Record
    , scale : DataScale
    , xCol : String
    , yCol : String
    }


type Msg
    = MouseMsg MouseEvent
    | SitesSelectedMsg (List Int)
    | XColSelectedMsg String
    | YColSelectedMsg String
    | ReceivedStats
        { sitesObserved : List StatsForSite
        , statNameLookup : List ( String, { name : String, description : String } )
        }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ReceivedStats { sitesObserved, statNameLookup } ->
            let
                variables =
                    sitesObserved
                        |> List.concatMap (.stats >> List.map Tuple.first)
                        |> List.foldl Set.insert Set.empty
                        |> Set.toList
                        |> List.sortBy String.toLower

                xCol =
                    "alpha"

                -- variables |> List.getAt 0 |> Maybe.withDefault ""
                yCol =
                    "phi"

                -- variables |> List.getAt 1 |> Maybe.withDefault ""
                records =
                    sitesObserved
                        |> List.filter (.stats >> List.any (\( k, v ) -> v /= Just 0.0))
                        |> recordsFromStats xCol yCol

                scale =
                    computeScale records
            in
                ( { model
                    | variables = variables
                    , statNames = Dict.fromList statNameLookup
                    , stats = sitesObserved
                    , xCol = xCol
                    , yCol = yCol
                    , displayedRecords = records
                    , scale = scale
                  }
                , Cmd.none
                )

        XColSelectedMsg col ->
            let
                records =
                    recordsFromStats col model.yCol model.stats

                scale =
                    computeScale records
            in
                ( { model | xCol = col, displayedRecords = records, scale = scale }, Cmd.none )

        YColSelectedMsg col ->
            let
                records =
                    recordsFromStats model.xCol col model.stats

                scale =
                    computeScale records
            in
                ( { model | yCol = col, displayedRecords = records, scale = scale }, Cmd.none )

        SitesSelectedMsg sites ->
            ( { model | selected = Set.fromList sites, flagged = Dict.empty }, Cmd.none )

        MouseMsg event ->
            case event.eventType of
                "mousedown" ->
                    let
                        p =
                            pixel2svg svgViewBox (PixelPoint { x = event.x, y = event.y })

                        selecting =
                            if inViewBox svgViewBox p then
                                Just ( p, p )
                            else
                                Nothing
                    in
                        ( { model | selecting = selecting, flagged = Dict.empty }, Cmd.none )

                "mousemove" ->
                    case model.selecting of
                        Just ( p1, _ ) ->
                            let
                                p2 =
                                    pixel2svg svgViewBox (PixelPoint { x = event.x, y = event.y })

                                selecting =
                                    Just ( p1, p2 )
                            in
                                ( { model | selecting = selecting }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                "mouseup" ->
                    case model.selecting of
                        Just ( p1_, _ ) ->
                            let
                                p2_ =
                                    pixel2svg svgViewBox (PixelPoint { x = event.x, y = event.y })

                                ( DataPoint p1, DataPoint p2 ) =
                                    ( svg2data model.scale p1_, svg2data model.scale p2_ )

                                ( x1, y1 ) =
                                    ( Basics.min p1.x p2.x, Basics.min p1.y p2.y )

                                ( x2, y2 ) =
                                    ( Basics.max p1.x p2.x, Basics.max p1.y p2.y )

                                newlySelected =
                                    model.displayedRecords
                                        |> List.filter (\d -> d.x > x1 && d.x < x2 && d.y > y1 && d.y < y2)
                                        |> List.map .siteId
                                        |> Set.fromList

                                selected =
                                    if event.ctrlKey then
                                        Set.union model.selected newlySelected
                                    else
                                        newlySelected
                            in
                                ( { model | selected = selected, selecting = Nothing }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )


type alias Record =
    { siteId : Int, x : Float, y : Float }


extractRecord : String -> String -> StatsForSite -> Maybe Record
extractRecord xCol yCol stats =
    let
        getValue col =
            stats.stats
                |> List.find (Tuple.first >> ((==) col))
                |> Maybe.map Tuple.second
                |> Maybe.join
                |> Result.fromMaybe "missing value"
    in
        Result.map2 (Record stats.id) (getValue xCol) (getValue yCol) |> Result.toMaybe


recordsFromStats : String -> String -> List StatsForSite -> List Record
recordsFromStats xCol yCol stats =
    List.map (extractRecord xCol yCol) stats |> Maybe.values


agg : (number -> number -> number) -> List number -> Maybe number
agg fn xs =
    case xs of
        [] ->
            Nothing

        x :: xs ->
            List.foldl fn x xs |> Just


drawScatter : Model -> List (Svg msg)
drawScatter model =
    let
        plot record =
            let
                (SvgPoint point) =
                    data2svg model.scale (DataPoint { x = record.x, y = record.y })
            in
                circle
                    [ point.x |> toString |> cx
                    , point.y |> toString |> cy
                    , r "6"
                    , fillOpacity "0.8"
                    , if Set.member record.siteId model.selected then
                        fill "red"
                      else
                        case Dict.get record.siteId model.flagged of
                            Just color ->
                                fill color

                            Nothing ->
                                fill "black"
                    ]
                    []

        xLabel =
            Dict.get model.xCol model.statNames |> Maybe.map .name |> Maybe.withDefault model.xCol

        yLabel =
            Dict.get model.yCol model.statNames |> Maybe.map .name |> Maybe.withDefault model.yCol
    in
        drawXAxis xLabel model.scale.minX model.scale.maxX
            ++ drawYAxis yLabel model.scale.minY model.scale.maxY
            ++ List.map plot model.displayedRecords


drawXAxis : String -> Float -> Float -> List (Svg msg)
drawXAxis label min max =
    let
        ticks =
            List.range 1 10
                |> List.map (toFloat >> ((*) 100) >> toString)
                |> List.map (\x -> line [ x1 x, x2 x, y1 "1000", y2 "1020", strokeWidth "1", stroke "black" ] [])

        maxValue =
            text_
                [ x "990"
                , y "1030"
                , textAnchor "end"
                , Html.Attributes.style [ ( "font-size", "20px" ) ]
                ]
                [ max |> formatNumber |> text ]

        minValue =
            text_
                [ x "0"
                , y "1030"
                , Html.Attributes.style [ ( "font-size", "20px" ) ]
                ]
                [ min |> formatNumber |> text ]

        labelText =
            text_
                [ x "500"
                , y "1050"
                , textAnchor "middle"
                , Html.Attributes.style [ ( "font-size", "30px" ) ]
                ]
                [ text label ]
    in
        (line [ x1 "0", x2 "1000", y1 "1000", y2 "1000", strokeWidth "1", stroke "black" ] []
            :: minValue
            :: maxValue
            :: labelText
            :: ticks
        )


drawYAxis : String -> Float -> Float -> List (Svg msg)
drawYAxis label min max =
    let
        ticks =
            List.range 1 10
                |> List.map (toFloat >> ((*) 100) >> ((-) 1000) >> toString)
                |> List.map (\y -> line [ y1 y, y2 y, x1 "0", x2 "-20", strokeWidth "1", stroke "black" ] [])

        maxValue =
            text_
                [ x "-10"
                , y "30"
                , textAnchor "end"
                , Html.Attributes.style [ ( "font-size", "20px" ) ]
                ]
                [ max |> formatNumber |> text ]

        minValue =
            text_
                [ x "-10"
                , y "1000"
                , textAnchor "end"
                , Html.Attributes.style [ ( "font-size", "20px" ) ]
                ]
                [ min |> formatNumber |> text ]

        labelText =
            text_
                [ x "500"
                , y "50"
                , textAnchor "middle"
                , transform "rotate(90)"
                , Html.Attributes.style [ ( "font-size", "30px" ) ]
                ]
                [ text label ]
    in
        (line [ y1 "0", y2 "1000", x1 "0", x2 "0", strokeWidth "1", stroke "black" ] []
            :: minValue
            :: maxValue
            :: labelText
            :: ticks
        )


svgViewBox2String : SvgViewBox -> String
svgViewBox2String { width, height, minX, minY, maxX, maxY } =
    [ minX, minY, maxX - minX, maxY - minY ] |> List.map toString |> String.join " "


viewPlot : Model -> Html.Html Msg
viewPlot model =
    let
        selectionBox =
            model.selecting
                |> Maybe.toList
                |> List.map
                    (\( SvgPoint p1, SvgPoint p2 ) ->
                        let
                            ( x_, y_ ) =
                                ( Basics.min p1.x p2.x, Basics.min p1.y p2.y )

                            ( w, h ) =
                                ( Basics.abs (p2.x - p1.x), Basics.abs (p2.y - p1.y) )
                        in
                            rect
                                [ x (toString x_)
                                , y (toString y_)
                                , width <| toString w
                                , height <| toString h
                                , fill "red"
                                , fillOpacity "0.4"
                                ]
                                []
                    )

        variableSelector selected select =
            Html.select [ Html.Events.onInput select ]
                (model.variables
                    |> List.map
                        (\v ->
                            Html.option
                                [ Html.Attributes.selected (v == selected)
                                , Html.Attributes.value v
                                ]
                                [ Dict.get v model.statNames
                                    |> Maybe.map .name
                                    |> Maybe.withDefault v
                                    |> Html.text
                                ]
                        )
                )
    in
        Html.div []
            [ Html.h3 [ Html.Attributes.style [ ( "text-align", "center" ) ] ]
                [ Html.text "Site Based Stat Relationships" ]
            , Html.div [ Html.Attributes.style [ ( "text-align", "center" ) ] ]
                [ variableSelector model.yCol YColSelectedMsg
                , Html.text " vs "
                , variableSelector model.xCol XColSelectedMsg
                ]
            , svg
                [ width <| toString svgViewBox.width
                , height <| toString svgViewBox.height
                , viewBox <| svgViewBox2String svgViewBox
                , Html.Attributes.id "plot"
                ]
                ((drawScatter model) ++ selectionBox)
            , Html.p [ Html.Attributes.style [ ( "width", "500px" ) ] ]
                [ Html.text <|
                    "The scatter plot shows relationships between site based statistics; "
                        ++ "each dot represents a single site.  If sites in the map are highlighted, "
                        ++ "the corresponding sites are highlighted in the same color in the scatter plot. "
                        ++ "You can brush sites in the plot by clicking and dragging to create a selection box. "
                        ++ "Doing so will highlight the selected points as well as those sites on the map and "
                        ++ "the species present at those sites in the tree.  Use the two drop down boxes to select "
                        ++ "the metrics to use for the X and Y axes."
                ]
            ]


view : Model -> Html.Html Msg
view model =
    let
        selectedSiteIds =
            model.selected |> Set.toList |> List.map toString |> String.join " "
    in
        Html.div
            -- [ Html.Events.on "keyup" (Decode.map KeyUp <| Decode.field "key" Decode.string)
            [ Html.Attributes.style
                [ ( "display", "flex" )
                , ( "flex-direction", "flex-row" )
                , ( "font-family", "sans-serif" )
                ]
            , Html.Attributes.tabindex 0
            ]
            [ viewPlot model
            , Html.div
                [ Html.Attributes.style [ ( "flex-grow", "1" ) ] ]
                [ Html.h3 [ Html.Attributes.style [ ( "text-align", "center" ) ] ]
                    [ Html.text "Site Map" ]
                , Html.div
                    [ Html.Attributes.class "leaflet-map"
                    , Html.Attributes.attribute "data-map-sites" selectedSiteIds
                    , Html.Attributes.style
                        [ ( "max-width", "900px" )
                        , ( "height", "500px" )
                        , ( "margin-left", "auto" )
                        , ( "margin-right", "auto" )
                        ]
                    ]
                    []
                ]
            ]


init : ( Model, Cmd Msg )
init =
    ( { selected = Set.empty
      , selecting = Nothing
      , flagged = Dict.empty
      , variables = []
      , statNames = Dict.empty
      , stats = []
      , displayedRecords = []
      , scale = DataScale 1 1 1 1
      , xCol = ""
      , yCol = ""
      }
    , requestStats ()
    )


subscriptions : Model -> Sub Msg
subscriptions =
    always <|
        Sub.batch
            [ mouseEvent MouseMsg
            , sitesSelected SitesSelectedMsg
            , statsForSites ReceivedStats
            ]


main : Program Never Model Msg
main =
    Html.program
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
