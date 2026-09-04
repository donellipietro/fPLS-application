from __future__ import annotations

import os
import sys

from paraview.simple import (
    Clip,
    ColorBy,
    CreateLayout,
    CreateView,
    GetColorTransferFunction,
    OpenDataFile,
    RemoveViewsAndLayouts,
    Render,
    SaveScreenshot,
    Show,
    UpdatePipeline,
    _DisableFirstRenderCameraReset,
)


_DisableFirstRenderCameraReset()
data_file, output_file = map(os.path.abspath, sys.argv[-2:])
RemoveViewsAndLayouts()
source = OpenDataFile(data_file)
UpdatePipeline(proxy=source)
bounds = source.GetDataInformation().GetBounds()
center = [0.5 * (bounds[i] + bounds[i + 1]) for i in (0, 2, 4)]
span = max(bounds[3] - bounds[2], bounds[5] - bounds[4])
field = "fPLS_intrinsic_CTRL_unit_H3"
clip = Clip(Input=source)
clip.ClipType = "Plane"
clip.ClipType.Origin = center
clip.ClipType.Normal = [1.0, 0.0, 0.0]

layout = CreateLayout(name="Intrinsic fPLS slider")
layout.SetSize(1200, 520)
views = []
for index, dataset in enumerate((source, clip)):
    view = CreateView("RenderView")
    view.ViewSize = [600, 520]
    view.Background = [1.0, 1.0, 1.0]
    view.OrientationAxesVisibility = 0
    view.CameraParallelProjection = 1
    display = Show(dataset, view)
    display.Representation = "Surface"
    ColorBy(display, ("POINTS", field))
    lookup = GetColorTransferFunction(field)
    lookup.ApplyPreset("Cool to Warm", True)
    limit = max(abs(value) for value in source.PointData[field].GetRange())
    lookup.RescaleTransferFunction(-limit, limit)
    display.SetScalarBarVisibility(view, False)
    view.CameraPosition = [center[0] + 3.0 * span, center[1], center[2]]
    view.CameraFocalPoint = center
    view.CameraViewUp = [0.0, 0.0, 1.0]
    view.CameraParallelScale = 0.55 * span
    Render(view)
    if index == 0:
        layout.AssignView(0, view)
    else:
        layout.AssignView(layout.SplitViewHorizontal(views[0]) + 1, view)
    views.append(view)

SaveScreenshot(output_file, layout, ImageResolution=[1200, 520], TransparentBackground=1)
