/*
Copyright (C) 2017, University of Kansas Center for Research

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
*/

"use strict";

var maps = {};
var mapLayers = {};

document.onmousemove = document.onmouseup = document.onmousedown = function(event) {
    const plot = document.getElementById("plot");
    if (plot == null) return;
    const rect = plot.getBoundingClientRect();
    if (event.clientX >= rect.left &&
        event.clientY >= rect.top &&
        event.clientX < rect.right &&
        event.clientY < rect.bottom
       ) {
        event.preventDefault();
        const data = {
            eventType: event.type,
            x: event.clientX - rect.left,
            y: event.clientY - rect.top,
            ctrlKey: event.ctrlKey
        };
        app.ports.mouseEvent.send(data);
    }
};

function configureMap(element) {
    var map = maps[element._leaflet_id];
    if (map == null) return;
    console.log("updating leaflet id", element._leaflet_id);

    var layers = mapLayers[element._leaflet_id];
    // if (layers != null) {
    //     layers.forEach(function(layer) {  map.removeLayer(layer); });
    // }

    var sites = element.dataset["mapSites"].split(" ");

    const node = nodeLookup.find(function(d) {
        let mapColumn = element.dataset["mapColumn"];
        return d.header == mapColumn || d.header.toLowerCase() == ("node_" + mapColumn);
    });
    const dataColumn = node && node.index;


    if (layers == null || layers.length === 0) {
        console.log("adding layer");
        mapLayers[element._leaflet_id] = [
            L.geoJSON(ancPam, {
                style: style(sites, dataColumn),
                filter: function(feature) {
                    const data = feature.properties.data;
                    return data["1"] || data["-1"] || data["2"];
                }
            }).addTo(map)
        ];
    } else {
        layers[0].setStyle(style(sites, dataColumn));
    }
}

function style(sites, dataColumn) {
    return function(feature) {
        const included =  sites.includes("" + feature.id);
        const data = feature.properties.data;

        if (dataColumn != null) {
            if (data["1"] && data["1"].includes(dataColumn)) {
                return {
                    fillOpacity: 0.6,
                    stroke: false,
                    fill: true,
                    fillColor: "blue"
                };
            }

            if (data["-1"] && data["-1"].includes(dataColumn)) {
                return {
                    fillOpacity: 0.6,
                    stroke: false,
                    fill: true,
                    fillColor: "red"
                };
            }

            if (data["2"] && data["2"].includes(dataColumn)) {
                return {
                    fillOpacity: 0.6,
                    stroke: false,
                    fill: true,
                    fillColor: "purple"
                };
            }
        }

        return {
            fillOpacity: 0.6,
            stroke: false,
            fill: included,
            fillColor: "red"
        };

    };
}

// var centers = turf.featureCollection(
//     turf.featureReduce(ancPam, function(centers, feature) {
//         return centers.concat(
//             turf.point([feature.properties.centerX, feature.properties.centerY], feature.properties)
//         );
//     }, [])
// );

var bbox = turf.bbox(ancPam);

var observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(m) {
        m.addedNodes.forEach(function(n) {
            if (n.getElementsByClassName == null) return;

            var elements = n.getElementsByClassName("leaflet-map");
            Array.prototype.forEach.call(elements, function(element) {
                var map = L.map(element, {worldCopyJump: true});

                L.tileLayer('http://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                    attribution: "© OpenStreetMap",
                    minZoom: 2,
                    maxZoom: 12
                }).addTo(map);

                map.fitBounds([
                    [bbox[1], bbox[0]], [bbox[3], bbox[2]]
                ]);

                var editableLayers = new L.FeatureGroup();
                map.addLayer(editableLayers);

                var drawControl = new L.Control.Draw({
                    draw: {
                        polyline: false,
                        marker: false,
                        circle: false,
                        circlemarker: false
                    }
                });
                map.addControl(drawControl);

                map.on(L.Draw.Event.CREATED, function(e) {
                    editableLayers.addLayer(e.layer);
                    const selection = editableLayers.toGeoJSON().features[0];
                    app.ports.sitesSelected.send(
                        turf.featureReduce(
                            sitesObserved,
                            function(sites, feature) {
                                return turf.booleanWithin(feature, selection) ?
                                    sites.concat(feature.id) :
                                    sites;
                            }, [])
                    );
                    editableLayers.clearLayers();
                });

                map.on(L.Draw.Event.DRAWSTART, function(e) {
                    editableLayers.clearLayers();
                });

                maps[element._leaflet_id] = map;
                console.log("added leaflet id", element._leaflet_id);
                configureMap(element);
            });
        });

        m.removedNodes.forEach(function(n) {
            if (n.getElementsByClassName == null) return;

            var elements = n.getElementsByClassName("leaflet-map");
            Array.prototype.forEach.call(elements, function(element) {
                if (element._leaflet_id != null) {
                    console.log("removing map with leaflet id", element._leaflet_id);
                    maps[element._leaflet_id].remove();
                    maps[element._leaflet_id] = null;
                    mapLayers[element._leaflet_id] = null;
                }
            });
        });

        if (m.type == "attributes") {
            configureMap(m.target);
        }
    });
});

observer.observe(document.body, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ["data-map-sites", "data-map-column"],
    attributeOldValue: true
});

var node = document.getElementById("app");
while(node.firstChild) { node.removeChild(node.firstChild);}
var app = Elm.StatsTreeMap.embed(node, {
    data: mcpaMatrix,
    taxonTree: taxonTree
});

//var app = Elm.StatsTreeMap.fullscreen({
//    data: mcpaMatrix,
//    taxonTree: taxonTree
//});

app.ports.statsForSites.send({
    sitesObserved: sitesObserved.features.map(function(feature) {
        return {id: feature.id, stats: Object.entries(feature.properties)};
    }),
    statNameLookup: Object.entries(statNameLookup)
});

