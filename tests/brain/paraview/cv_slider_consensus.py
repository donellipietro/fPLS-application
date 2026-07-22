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
    GetScalarBar,
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
        elif argument.endswith("cv_slider_consensus.py"):
            candidate_dirs.append(os.path.dirname(os.path.abspath(argument)))
    candidate_dirs.extend([
        os.getcwd(),
        os.path.join(
            os.getcwd(),
            "results",
            "brain",
            "aggregate",
            "out_of_sample",
            "cv_slider_consensus_maps",
            "paraview",
        ),
    ])
    for directory in candidate_dirs:
        candidate = os.path.join(directory, "cv_slider_consensus.vtu")
        if os.path.exists(candidate):
            return os.path.abspath(candidate)
    searched = "\n  ".join(os.path.abspath(path) for path in candidate_dirs)
    raise FileNotFoundError(f"Missing cv_slider_consensus.vtu; searched:\n  {searched}")


DATA_FILE = find_data_file()
BASE_DIR = os.path.dirname(DATA_FILE)
STATE_FILE = os.path.join(BASE_DIR, "cv_slider_consensus.pvsm")
SCREENSHOT_FILE = os.path.join(BASE_DIR, "cv_slider_consensus.png")
COMPONENTS = (3, 4, 5, 6)

RemoveViewsAndLayouts()

source = OpenDataFile(DATA_FILE)
RenameProxy(source, "sources", "Repeated-CV slider consensus maps")
UpdatePipeline(proxy=source)
bounds = source.GetDataInformation().GetBounds()
center = [
    0.5 * (bounds[0] + bounds[1]),
    0.5 * (bounds[2] + bounds[3]),
    0.5 * (bounds[4] + bounds[5]),
]
camera_span = max(bounds[3] - bounds[2], bounds[5] - bounds[4])

limit = 0.0
for h in COMPONENTS:
    lower, upper = source.PointData[f"slider_consensus_CTRL_unit_H{h}"].GetRange()
    limit = max(limit, abs(lower), abs(upper))

views = []
for index, h in enumerate(COMPONENTS):
    view = CreateView("RenderView")
    view.ViewSize = [430, 440]
    view.Background = [1.0, 1.0, 1.0]
    view.OrientationAxesVisibility = 0
    view.CameraParallelProjection = 1

    field = f"slider_consensus_CTRL_unit_H{h}"
    display = Show(source, view)
    display.Representation = "Surface"
    ColorBy(display, ("POINTS", field))
    lookup_table = GetColorTransferFunction(field)
    lookup_table.ApplyPreset("Cool to Warm (Extended)", True)
    lookup_table.RescaleTransferFunction(-limit, limit)
    display.SetScalarBarVisibility(view, index == len(COMPONENTS) - 1)
    if index == len(COMPONENTS) - 1:
        scalar_bar = GetScalarBar(lookup_table, view)
        scalar_bar.Orientation = "Vertical"
        scalar_bar.WindowLocation = "Lower Right Corner"
        scalar_bar.Title = ""
        scalar_bar.ComponentTitle = ""

    label = Text(registrationName=f"consensus_H{h}_label", Text=f"Consensus slider | H={h}")
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

layout = GetLayout(views[0])
if layout is None:
    layout = CreateLayout(name="Repeated-CV slider consensus")
for candidate_layout in GetLayouts().values():
    for view in views:
        if candidate_layout.GetViewLocation(view) != -1:
            candidate_layout.RemoveView(view)
layout.Reset()
layout.SetSize(1800, 500)
layout.AssignView(0, views[0])
for index in range(1, len(views)):
    location = layout.SplitViewHorizontal(views[index - 1]) + 1
    layout.AssignView(location, views[index])

for index, view in enumerate(views[1:], start=1):
    AddCameraLink(views[0], view, f"cv_slider_consensus_camera_{index}")

EqualizeViewsBoth(layout)
SetActiveView(views[0])
SaveState(STATE_FILE)
SaveScreenshot(SCREENSHOT_FILE, layout, ImageResolution=[1800, 500])
Render()

print(f"Loaded {DATA_FILE}")
print(f"Saved reusable ParaView state to {STATE_FILE}")
print(f"Saved scene preview to {SCREENSHOT_FILE}")
