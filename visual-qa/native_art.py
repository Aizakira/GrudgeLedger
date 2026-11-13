"""Optional WoW Classic reference textures for offline previews; never packaged."""
from hashlib import sha256
from pathlib import Path
from urllib.request import urlopen


CACHE = Path(__file__).resolve().parent / "renders" / "native"
# Git mirror of the extracted Blizzard UI, Classic 1.13.5 (34911).
SOURCE = "https://raw.githubusercontent.com/Gethe/wow-ui-textures/312a6e61bab69370c65ccc0a08f1075d62196294/"
TEXTURES = {
    "ACHIEVEMENTFRAME/UI-Achievement-IconFrame.PNG": "78a47130332791b276b1b6474a191cebfd16a56770850f3d1e6dcd4006fd657e",
    "ICONS/Ability_DualWield.PNG": "2af79363ad391968679b5b92a001cff742a4d6b1cb823b60fc02d87c5b4b0149",
    "ICONS/Ability_Rogue_FeignDeath.PNG": "7cfd14b389e89fd21da4dd8c854ba23d34bb080d79af89807b6589f78dd41e18",
    "ICONS/Ability_Warrior_Challange.PNG": "a0d2479627399aec6027fbeac857e8000741b4b80d19c284b819a4e761eb50ef",
    "ICONS/Ability_Warrior_Charge.PNG": "bcf188e59dfaf2f1112969ed4a8ead480be24f83939dbe9304eb726b06ffb033",
    "ICONS/INV_Misc_Book_09.PNG": "a0dc6f294133afd3cbf5a54389fe55cb3123a643678d9594469615b63f10d300",
    "ICONS/INV_BannerPVP_01.PNG": "18027f556553dc228cedea513f5eb45388cbe8d2786efc4f49f163116afa00da",
    "ICONS/INV_BannerPVP_02.PNG": "3d0b96afed9b0c9007c21d18138c9de55705fb9624b882e4cb82590442c880d2",
    "Buttons/UI-OptionsButton.PNG": "f4afedd1e3669d860d3f31e705ffd79fef054cf50a696b38bb06b6a901701e8f",
    "Buttons/UI-ScrollBar-ScrollDownButton-Up.PNG": "33b783b69a9c1744ce967c309af3e669bb8accc24453aacc158aa265e72b8989",
    "Buttons/UI-Quickslot2.PNG": "a9d4a63d00423f73b9dfc35454647d8f69241ba9b0e8feda1cd0a749e6ef6669",
    "CHARACTERFRAME/TempPortraitAlphaMask.PNG": "6b65ef6abb7899cd31fa2ecd1774aa747ecfc21b84f86159861805806a634f31",
    "ICONS/INV_Misc_QuestionMark.PNG": "6da3bffad0892ec7d7de4d0faac52939706f3ca81a56d818cea9bd611067a282",
    "ICONS/Spell_Nature_CorrosiveBreath.PNG": "d73d45bc869125b69691236823dda1ee8b35313915050b670a12b9e2c3c9b5f1",
    "Glues/CHARACTERCREATE/CharacterCreateIcons.PNG": "6b5b3ac6495c18157f1d65c01930d72cb69081cbed7ac23dda10a0d99fa24455",
    "Glues/CHARACTERCREATE/UI-CHARACTERCREATE-CLASSES.PNG": "484a654dcac5b59a43d83a246402e8b43222905759d7ab0255aec1a60962cc0f",
    "MINIMAP/MiniMap-TrackingBorder.PNG": "ae9c3f0136d0a2d0d4cb44e896762111f54812bcb1a219b8db40595fb15cc1b8",
    "MINIMAP/UI-Minimap-Background.PNG": "b998f84f7576ac840b1f0e9b6ae3bf193dcbc094bd29e1909e4bac3eef454bac",
}
PATHS = {("interface/" + name[:-4]).lower(): CACHE / name for name in TEXTURES}

if __name__ == "__main__":
    for name, expected in TEXTURES.items():
        dest = CACHE / name
        if dest.is_file() and sha256(dest.read_bytes()).hexdigest() == expected:
            continue
        with urlopen(SOURCE + name, timeout=20) as response:
            data = response.read(512 * 1024)
        if sha256(data).hexdigest() != expected:
            raise ValueError("Unexpected contents for " + name)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
    print(f"{len(TEXTURES)} verified reference textures available in {CACHE}")
