import functools
import os
import subprocess
import sys
import tempfile
from contextlib import ExitStack
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence, Union
from zipfile import ZipFile

from SCons.Node.FS import File as SConsFile
from SCons.Script.SConscript import SConsEnvironment

PRINTABLES_TARGET = "printables"
DIST_PRINTABLES_ZIP = "dist-printables.zip"
LIBRARIES_ZIP = "libraries.zip"
IMAGE_RENDER_SIZE = "1200x900"
IMAGE_TARGETS = {
    "images/readme": "400x300",
    "images/publish": IMAGE_RENDER_SIZE,
}


def openscad_builder():
    def add_deps_target(target, source, env):
        target.append("${TARGET.name}.deps")
        return target, source

    return Builder(
        action=(
            "$OPENSCAD -m make"
            " -o $TARGET -d ${TARGET}.deps"
            " $SOURCE"
            " $OPENSCAD_ARGS"
        ),
        emitter=add_deps_target,
    )


def run(
    cmd: list,
    *args: Any,
    quiet: bool = False,
    check: bool = True,
    **kwargs: Any,
) -> subprocess.CompletedProcess:
    if not quiet:
        print("+", " ".join([str(c) for c in cmd]), file=sys.stderr)
    return subprocess.run(cmd, *args, check=check, **kwargs)


def remove_prefix(value: str, prefixes: Union[str, Sequence[str]]) -> str:
    for prefix in [prefixes] if isinstance(prefixes, str) else prefixes:
        if value.startswith(prefix):
            return value[len(prefix) :]
    return value


def openscad_var_args(
    vals: Dict[str, any] = None, for_subprocess: bool = False
) -> Sequence[str]:
    def _val_args(k, v):
        if isinstance(v, str):
            v = f'"{v}"' if for_subprocess else f"'\"{v}\"'"
        return ["-D", f"{k}={v}"]

    return [arg for k, v in (vals or {}).items() for arg in _val_args(k, v)]


class ModelBuilder:
    def __init__(self, env: SConsEnvironment):
        self.env = env
        self.build_dir = Dir(".")
        self.common_build_dir = Dir("..")
        self.src_dir = Dir(".").srcdir
        self.src_dir_path = Path(str(self.src_dir))
        self.model_dir = self.src_dir_path.name
        self.publish_images = set()

    def ref_filter(fn: Callable[..., Any]) -> Callable[..., Any]:
        def _wrapper(self, *args: Any) -> Any:
            if not self._allowed_by_filter:
                return
            fn(self, *args)

        return _wrapper

    @ref_filter
    def add_default_targets(self) -> None:
        if PRINTABLES_TARGET in BUILD_TARGETS:
            self.add_printables_zip_targets()

    @ref_filter
    def STL(
        self,
        model_file: str,
        stl_file: str,
        stl_vals: Optional[Dict[str, Any]] = None,
        model_dependencies: Optional[Sequence[str]] = None,
    ) -> None:
        self.env.openscad(
            target=stl_file,
            source=[model_file] + (model_dependencies or []),
            OPENSCAD_ARGS=" ".join(openscad_var_args(stl_vals)),
        )

    def make_doc(
        self,
        target: Sequence[SConsFile],
        source: Sequence[SConsFile],
        env: SConsEnvironment,
    ) -> None:
        with tempfile.TemporaryDirectory() as td:
            tdp = Path(td)
            md_file = tdp / "input.md"
            md_text = Path(source[0].path).read_text()
            for rpath, rep_path in [
                ("/_static/", Path(Dir("#").path) / "_static"),
                (
                    ("../images/readme", "images/readme"),
                    Path(self.src_dir.path) / "images" / "publish",
                ),
            ]:
                rpath_abs = str(rep_path.absolute()) + "/"
                for rp in [rpath] if isinstance(rpath, str) else rpath:
                    md_text = md_text.replace(rp, rpath_abs)
            with open(md_file, "w") as f:
                f.write(md_text)
            cmd = [
                "pandoc",
                "-f",
                "commonmark",
                md_file,
                "-o",
                target[0].path,
                "--table-of-contents",
                "--toc-depth=4",
                "--number-sections",
                "--pdf-engine=xelatex",
            ]
            for pandoc_var in [
                "fontsize=12pt",
                "colorlinks=true",
                "linestretch=1.0",
                (
                    " geometry:"
                    '"top=1.5cm, bottom=2.5cm, left=1.5cm, right=1.5cm"'
                ),
                "papersize=letter",
            ]:
                cmd += ["--variable", pandoc_var]
            run(cmd)

    def Document(
        self,
        source: str,
        target: str,
        image_dependencies: Optional[Sequence[str]] = None,
    ) -> None:
        self.env.Command(
            target, [source] + [image_dependencies or []], self.make_doc
        )

    def Image(
        self,
        model_file: str,
        target: str,
        stl_vals: Optional[Union[List[Dict[str, Any]], Dict[str, Any]]] = None,
        camera: Optional[str] = None,
        view_options: Optional[str] = None,
        delay=75,
    ) -> None:
        image_targets = {
            f"{self.src_dir}/{image_path}/{target}": size
            for image_path, size in IMAGE_TARGETS.items()
        }
        func = functools.partial(
            self.render_image,
            stl_vals_list=(
                [stl_vals]
                if isinstance(stl_vals, dict)
                else (stl_vals or [[]])
            ),
            image_targets=image_targets,
            camera=camera,
            view_options=view_options,
            delay=delay,
        )
        func.__name__ = self.render_image.__name__
        self.env.NoClean(
            self.env.Command(image_targets.keys(), model_file, func)
        )
        self.publish_images.add(
            File(f"{self.src_dir}/images/publish/{target}")
        )

    @functools.cached_property
    def library_files(self) -> Sequence[Path]:
        return [
            lib_file
            for lib_glob in [
                fn.glob("*.scad")
                for fn in self.src_dir.glob("*")
                if Path(str(fn)).is_symlink()
            ]
            for lib_file in lib_glob
        ]

    def render_image(
        self,
        target: Sequence[SConsFile],
        source: Sequence[SConsFile],
        env: SConsEnvironment,
        image_targets: Optional[Dict[str, str]] = None,
        stl_vals_list: Optional[Sequence[Dict[str, Any]]] = None,
        delay: int = 75,
        camera: Optional[str] = None,
        view_options: Optional[str] = None,
    ) -> None:
        def _render_single_image(
            image_target: str, stl_vals: Dict[str, Any], size=None
        ) -> None:
            render_args = openscad_var_args(stl_vals, for_subprocess=True)
            if camera:
                render_args += [f"--camera={camera}"]
            if view_options:
                render_args += [f"--view={view_options}"]
            run(
                [
                    self.env["OPENSCAD"],
                    source[0].path,
                    f"--colorscheme={'DeepOcean'}",
                    f"--imgsize={size}",
                    "-o",
                    str(image_target),
                ]
                + render_args
            )

        with tempfile.TemporaryDirectory() as td:
            tdp = Path(td)
            # Render frames
            frames: List[str] = []
            for i, frame_stl_vals in enumerate(stl_vals_list):
                fn = tdp / f"image_{i:05d}.png"
                frames.append(fn)
                _render_single_image(
                    fn, frame_stl_vals, IMAGE_RENDER_SIZE.replace("x", ",")
                )
            for tt in target:
                cmd = ["convert", "-resize", image_targets[tt.abspath]]
                if target[0].suffix == ".gif":
                    cmd += ["-loop", "0", "-delay", str(delay)]
                run(cmd + frames + [tt.path])

    def add_printables_zip_targets(self) -> None:
        sources = (
            set(self.src_dir.glob("*.scad"))
            | set(self.build_dir.glob("*.pdf"))
            | set(self.build_dir.glob("*.stl"))
            | set(self.library_files)
            | set(self.publish_images)
        )
        self.env.Command(
            f"{self.common_build_dir}/printables-{self.model_dir}.zip",
            sorted(list(sources)),
            self.make_zip,
        )

    def zip_file_dest(self, source: Union[str, Path]) -> str:
        dest_stripped = remove_prefix(
            str(source),
            [str(self.build_dir) + "/", str(self.src_dir) + "/"],
        )
        if dest_stripped.startswith("images"):
            if "readme" in dest_stripped:
                return None
            return "images/" + Path(dest_stripped).name
        elif dest_stripped.endswith(".stl"):
            return "stl/" + Path(dest_stripped).name
        elif dest_stripped.endswith(".pdf"):
            return "doc/" + Path(dest_stripped).name
        return str(dest_stripped)

    def make_zip(
        self,
        target: Sequence[SConsFile],
        source: Sequence[SConsFile],
        env: SConsEnvironment,
    ) -> None:
        with ExitStack() as stack:
            tdp = None
            libraries_zip = None
            if self.library_files:
                tdp = Path(stack.enter_context(tempfile.TemporaryDirectory()))
                libraries_zip = tdp / LIBRARIES_ZIP
                with ZipFile(str(libraries_zip), mode="w") as z:
                    for lf in self.library_files:
                        z.write(
                            str(lf),
                            remove_prefix(
                                str(lf),
                                [
                                    str(self.build_dir) + "/",
                                    str(self.src_dir) + "/",
                                ],
                            ),
                        )
            with ZipFile(str(target[0]), mode="w") as z:
                if libraries_zip:
                    z.write(libraries_zip, LIBRARIES_ZIP)
                for ss in source:
                    if ss in self.library_files:
                        continue
                    zdest = self.zip_file_dest(ss)
                    if not zdest:
                        continue
                    z.write(str(ss), zdest)

    @functools.cached_property
    def _allowed_by_filter(self) -> bool:
        prev_ref = self.env.get("PREV_REF")
        if not prev_ref:
            return True
        try:
            dirs = {
                fn.split(os.sep)[0]
                for fn in run(
                    ["git", "diff", f"{prev_ref}...@", "--name-only", "--"],
                    quiet=True,
                    capture_output=True,
                    text=True,
                ).stdout.splitlines()
                if fn.endswith(".scad")
            }
            if self.src_dir_path.name not in dirs:
                return False
            print(
                f"Including model directory {self.model_dir}"
                f" changed since {prev_ref}"
            )
        except subprocess.CalledProcessError as e:
            print(f"Ignoring git diff error: {e}")
            pass
        return True
