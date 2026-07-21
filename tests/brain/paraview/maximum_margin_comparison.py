from __future__ import annotations

import os
import sys

from paraview.simple import (
    AddCameraLink,
    ColorBy,
    CreateLayout,
    CreateView,
    EqualizeViewsBoth,
    GetColorTransferFunction,
    GetLayout,
    GetLayouts,
    OpenDataFile,
    RemoveViewsAndLayouts,
    RenameProxy,
    Render,
    ResetCamera,
    SaveScreenshot,
    SaveState,
    SetActiveSource,
    SetActiveView,
    Show,
    Text,
    UpdatePipeline,
    _DisableFirstRenderCameraReset,
)


_DisableFirstRenderCameraReset()


def find_data_file():
    candidate_dirs = []
    configured = os.environ.get("FPLS_PARAVIEW_DATA_DIR")
    if configured:
        candidate_dirs.append(configured)
    script_name = globals().get("__file__")
    if script_name and not script_name.startswith("<"):
        candidate_dirs.append(os.path.dirname(os.path.abspath(script_name)))
    for argument in sys.argv:
        if argument.startswith("--script="):
            candidate_dirs.append(os.path.dirname(os.path.abspath(argument.split("=", 1)[1])))
        elif argument.endswith("maximum_margin_comparison.py"):
            candidate_dirs.append(os.path.dirname(os.path.abspath(argument)))
    candidate_dirs.extend([
        os.getcwd(),
        os.path.join(
            os.getcwd(),
            "results",
            "brain",
            "aggregate",
            "h_stability",
            "paraview",
        ),
    ])
    for directory in candidate_dirs:
        candidate = os.path.join(directory, "maximum_margin_comparison.vtu")
        if os.path.exists(candidate):
            return os.path.abspath(candidate)
    searched = "\n  ".join(os.path.abspath(path) for path in candidate_dirs)
    raise FileNotFoundError(f"Missing maximum_margin_comparison.vtu; searched:\n  {searched}")


DATA_FILE = find_data_file()
BASE_DIR = os.path.dirname(DATA_FILE)
STATE_FILE = os.path.join(BASE_DIR, "maximum_margin_comparison.pvsm")
SCREENSHOT_FILE = os.path.join(BASE_DIR, "maximum_margin_comparison.png")

RemoveViewsAndLayouts()

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
    ("f", "SVM slider (CTRL+)"),
    ("gamma", "SVM coefficient (CTRL+)"),
    ("beta", "PLS beta (CTRL+)"),
]
components = (3, 4, 5, 6)

row_ranges = {}
for prefix, _ in rows:
    maximum = 0.0
    for h in components:
        array = source.PointData[f"{prefix}_CTRL_unit_H{h}"]
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

        field = f"{prefix}_CTRL_unit_H{h}"
        display = Show(source, view)
        display.Representation = "Surface"
        ColorBy(display, ("POINTS", field))
        lookup_table = GetColorTransferFunction(field)
        lookup_table.ApplyPreset("Cool to Warm", True)
        limit = row_ranges[prefix]
        lookup_table.RescaleTransferFunction(-limit, limit)
        display.SetScalarBarVisibility(view, False)

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

layout = GetLayout(views[0])
if layout is None:
    layout = CreateLayout(name="Maximum-margin comparison")
for candidate_layout in GetLayouts().values():
    for view in views:
        if candidate_layout.GetViewLocation(view) != -1:
            candidate_layout.RemoveView(view)
layout.Reset()
layout.SetSize(1800, 1050)
for row_index in range(len(rows)):
    for column_index in range(len(components)):
        view = view_grid[(row_index, column_index)]
        if row_index == 0 and column_index == 0:
            layout.AssignView(0, view)
        elif row_index == 0:
            location = layout.SplitViewHorizontal(view_grid[(row_index, column_index - 1)]) + 1
            layout.AssignView(location, view)
        else:
            location = layout.SplitViewVertical(view_grid[(row_index - 1, column_index)]) + 1
            layout.AssignView(location, view)

for index, view in enumerate(views[1:], start=1):
    AddCameraLink(views[0], view, f"maximum_margin_camera_{index}")

EqualizeViewsBoth(layout)
SetActiveView(views[0])
SaveState(STATE_FILE)
SaveScreenshot(SCREENSHOT_FILE, layout, ImageResolution=[1800, 1050])
Render()

print(f"Loaded {DATA_FILE}")
print(f"Saved reusable ParaView state to {STATE_FILE}")
print(f"Saved scene preview to {SCREENSHOT_FILE}")
