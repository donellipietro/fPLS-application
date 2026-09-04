from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

from paraview.simple import (
    Clip,
    ColorBy,
    CreateView,
    GetColorTransferFunction,
    GetScalarBar,
    OpenDataFile,
    RemoveViewsAndLayouts,
    Render,
    SaveScreenshot,
    Show,
    UpdatePipeline,
    _DisableFirstRenderCameraReset,
)


if len(sys.argv) != 3:
    raise SystemExit("usage: pvpython A_slider.py INPUT.vtu OUTPUT_DIRECTORY")

DATA_FILE = Path(sys.argv[1]).resolve()
OUTPUT_DIRECTORY = Path(sys.argv[2]).resolve()
STATES = ("SCHZ", "critical", "CTRL")
# Three panels span the manuscript's 174 mm-wide page at final size.
VIEW_SIZE = [150, 106]  # 52.9 x 37.4 mm at 72 points per inch.
COLOURBAR_SIZE = [250, 60]
RASTER_SCALE = 8
RASTER_DPI = 72 * RASTER_SCALE
MAGICK = shutil.which("magick")

# Recovered from the prior paper's approved loading/mean visualizations.
EXTERNAL_CAMERA = {
    "position": [121.66472590194077, 54.37958524335819, 91.55748593696407],
    "focal_point": [32.50018500293476, 38.83631284372253, 21.450814308897833],
    "view_up": [-0.516649496302067, -0.41473291508836935, 0.749045997995533],
}
SECTIONAL_CAMERA = {
    "position": [-61.28130760635197, 35.70083327649345, 21.450814308897833],
    "focal_point": [32.50018500293476, 38.83631284372253, 21.450814308897833],
    "view_up": [0.0, 0.0, 1.0],
}
CLIP_ORIGIN = [32.50018500293476, 38.83631284372253, 21.450814308897833]


def export_panel(dataset, field, camera, filename, lower, upper):
    view = CreateView("RenderView")
    view.ViewSize = VIEW_SIZE
    view.Background = [1.0, 1.0, 1.0]
    view.OrientationAxesVisibility = 0
    view.CameraParallelProjection = 0
    view.CameraViewAngle = 25.0

    display = Show(dataset, view)
    display.Representation = "Surface"
    ColorBy(display, ("POINTS", field))
    lookup = GetColorTransferFunction(field)
    # Established connectivity-map palette: its range is the shared observed
    # state range, not the signed slider's symmetric +/- maximum.
    lookup.ApplyPreset("Cool to Warm (Extended)", True)
    lookup.RescaleTransferFunction(lower, upper)
    display.SetScalarBarVisibility(view, False)
    view.CameraPosition = camera["position"]
    view.CameraFocalPoint = camera["focal_point"]
    view.CameraViewUp = camera["view_up"]
    Render(view)

    with TemporaryDirectory() as directory:
        raster = Path(directory) / "panel.png"
        SaveScreenshot(str(raster), view, ImageResolution=[value * RASTER_SCALE for value in VIEW_SIZE])
        subprocess.run(
            [MAGICK, str(raster), "-units", "PixelsPerInch", "-density", str(RASTER_DPI), str(filename)],
            check=True,
        )


def export_colourbar(dataset, field, filename, lower, upper):
    view = CreateView("RenderView")
    view.ViewSize = COLOURBAR_SIZE
    view.Background = [1.0, 1.0, 1.0]
    view.OrientationAxesVisibility = 0

    display = Show(dataset, view)
    ColorBy(display, ("POINTS", field))
    lookup = GetColorTransferFunction(field)
    lookup.ApplyPreset("Cool to Warm (Extended)", True)
    lookup.RescaleTransferFunction(lower, upper)
    display.SetScalarBarVisibility(view, True)
    display.Visibility = 0
    scalar_bar = GetScalarBar(lookup, view)
    scalar_bar.Orientation = "Horizontal"
    scalar_bar.WindowLocation = "Any Location"
    scalar_bar.Position = [0.13, 0.35]
    scalar_bar.ScalarBarLength = 0.74
    scalar_bar.ScalarBarThickness = 14
    scalar_bar.Title = ""
    scalar_bar.ComponentTitle = ""
    scalar_bar.LabelFontSize = 10
    scalar_bar.LabelFormat = "%-#5.2g"
    scalar_bar.Visibility = 1
    Render(view)

    with TemporaryDirectory() as directory:
        raster = Path(directory) / "colourbar.png"
        SaveScreenshot(str(raster), view, ImageResolution=[value * RASTER_SCALE for value in COLOURBAR_SIZE])
        subprocess.run(
            [MAGICK, str(raster), "-units", "PixelsPerInch", "-density", str(RASTER_DPI), str(filename)],
            check=True,
        )


if not DATA_FILE.is_file():
    raise FileNotFoundError(f"Missing Figure 9 VTU: {DATA_FILE}")
if MAGICK is None:
    raise FileNotFoundError("ImageMagick executable 'magick' was not found on PATH")

OUTPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)
_DisableFirstRenderCameraReset()
RemoveViewsAndLayouts()
source = OpenDataFile(str(DATA_FILE))
UpdatePipeline(proxy=source)
fields = {state: f"state_{state}" for state in STATES}
missing = set(fields.values()) - set(source.PointData.keys())
if missing:
    raise KeyError(f"Missing state fields: {sorted(missing)}")

# Keep the approved Figure 9 colour scale fixed when representative states change.
lower, upper = -0.085793325446014534, 0.44488837701340167

clip = Clip(Input=source)
clip.ClipType = "Plane"
clip.ClipType.Origin = CLIP_ORIGIN
clip.ClipType.Normal = [-1.0, 0.0, 0.0]
clip.Invert = 1

for state, field in fields.items():
    export_panel(source, field, EXTERNAL_CAMERA, OUTPUT_DIRECTORY / f"{state}_external.pdf", lower, upper)
    export_panel(clip, field, SECTIONAL_CAMERA, OUTPUT_DIRECTORY / f"{state}_sectional.pdf", lower, upper)
export_colourbar(source, fields["SCHZ"], OUTPUT_DIRECTORY / "colourbar.pdf", lower, upper)

print(f"Shared connectivity-state range: [{lower:.17g}, {upper:.17g}]")
