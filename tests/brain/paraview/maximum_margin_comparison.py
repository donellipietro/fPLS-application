from __future__ import annotations

import os

from paraview.simple import (
    AddCameraLink,
    ColorBy,
    CreateLayout,
    CreateView,
    EqualizeViewsBoth,
    GetColorTransferFunction,
    OpenDataFile,
    RemoveViewsAndLayouts,
    RenameProxy,
    Render,
    ResetCamera,
    SaveState,
    SetActiveSource,
    SetActiveView,
    Show,
    Text,
    UpdatePipeline,
    _DisableFirstRenderCameraReset,
)


_DisableFirstRenderCameraReset()

BASE_DIR = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
DATA_FILE = os.path.join(BASE_DIR, "maximum_margin_comparison.vtu")
STATE_FILE = os.path.join(BASE_DIR, "maximum_margin_comparison.pvsm")

if not os.path.exists(DATA_FILE):
    raise FileNotFoundError(f"Missing generated ParaView data: {DATA_FILE}")

RemoveViewsAndLayouts()
layout = CreateLayout(name="Maximum-margin comparison")
layout.SetSize(1800, 1050)

source = OpenDataFile(DATA_FILE)
RenameProxy(source, "sources", "fPLS maximum-margin fields")
UpdatePipeline(proxy=source)
bounds = source.GetDataInformation().GetBounds()
center = [
    0.5 * (bounds[0] + bounds[1]),
    0.5 * (bounds[2] + bounds[3]),
    0.5 * (bounds[4] + bounds[5]),
]
camera_span = max(bounds[3] - bounds[2], bounds[5] - bounds[4])

rows = [
    ("beta", "PLS beta (SCHZ oriented)"),
    ("gamma", "SVM classifier coefficient"),
    ("f", "SVM reconstruction loading"),
]
components = (3, 4, 5, 6)

row_ranges = {}
for prefix, _ in rows:
    maximum = 0.0
    for h in components:
        array = source.PointData[f"{prefix}_SCHZ_unit_H{h}"]
        lower, upper = array.GetRange()
        maximum = max(maximum, abs(lower), abs(upper))
    row_ranges[prefix] = maximum

views = []
view_grid = {}
for row_index, (prefix, title) in enumerate(rows):
    for column_index, h in enumerate(components):
        view = CreateView("RenderView")
        view.ViewSize = [430, 320]
        view.Background = [1.0, 1.0, 1.0]
        view.OrientationAxesVisibility = 0
        view.CameraParallelProjection = 1
        if row_index == 0 and column_index == 0:
            layout.AssignView(0, view)
        elif row_index == 0:
            location = layout.SplitViewHorizontal(view_grid[(row_index, column_index - 1)])
            layout.AssignView(location, view)
        else:
            location = layout.SplitViewVertical(view_grid[(row_index - 1, column_index)])
            layout.AssignView(location, view)

        field = f"{prefix}_SCHZ_unit_H{h}"
        display = Show(source, view)
        display.Representation = "Surface"
        ColorBy(display, ("POINTS", field))
        lookup_table = GetColorTransferFunction(field)
        lookup_table.ApplyPreset("Cool to Warm", True)
        limit = row_ranges[prefix]
        lookup_table.RescaleTransferFunction(-limit, limit)
        display.SetScalarBarVisibility(view, column_index == len(components) - 1)

        label = Text(registrationName=f"{prefix}_H{h}_label", Text=f"{title} | H={h}")
        label_display = Show(label, view)
        label_display.WindowLocation = "Upper Center"
        label_display.FontSize = 13
        label_display.Color = [0.1, 0.1, 0.1]

        SetActiveSource(source)
        SetActiveView(view)
        ResetCamera(view)
        view.CameraPosition = [center[0] + 3.0 * camera_span, center[1], center[2]]
        view.CameraFocalPoint = center
        view.CameraViewUp = [0.0, 0.0, 1.0]
        view.CameraParallelScale = 0.55 * camera_span
        Render(view)
        views.append(view)
        view_grid[(row_index, column_index)] = view

for index, view in enumerate(views[1:], start=1):
    AddCameraLink(views[0], view, f"maximum_margin_camera_{index}")

EqualizeViewsBoth(layout)
SetActiveView(views[0])
SaveState(STATE_FILE)
Render()

print(f"Loaded {DATA_FILE}")
print(f"Saved reusable ParaView state to {STATE_FILE}")
