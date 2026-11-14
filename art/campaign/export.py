"""Export the editable campaign PNG layers to textures supported by the client."""
from pathlib import Path

from PIL import Image

source = Path(__file__).resolve().parent
media = source.parents[1] / "GrudgeLedger" / "Media"
sizes = {
    "JournalBookSurface": (1024, 1024),
    "JournalButtons": (512, 512),
    "JournalDialog": (512, 512),
    "JournalTitlePlate": (512, 64),
    "JournalWordmark": (512, 128),
    "JournalMedallion": (128, 128),
    "PortraitBezel": (128, 128),
    "LevelMedallion": (64, 64),
    "JournalSettings": (64, 64),
    "JournalClose": (64, 64),
    "LedgerBook": (256, 256),
}

if __name__ == "__main__":
    for name, size in sizes.items():
        with Image.open(source / f"{name}.png") as layer:
            image = layer.convert("RGBA").resize(size, Image.Resampling.LANCZOS)
            image.save(media / f"{name}.tga", compression=None)
