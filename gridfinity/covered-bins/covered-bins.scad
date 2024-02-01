/*
 * Gridfinity Bins with Lids
 * By smkent (GitHub) / bulbasaur0 (Printables)
 *
 * Licensed under Creative Commons (4.0 International License) Attribution
 */

include <gridfinity-rebuilt-openscad/gridfinity-rebuilt-utility.scad>;

// ===== PARAMETERS ===== //

/* [Setup Parameters] */
$fa = 8;
$fs = 0.25;

/* [General Settings] */

Part = "both_closed"; // [bin: Bin, lid: Lid, both_closed: Both - lid closed, both_open: Both - lid open, bin_slice: Bin slice for print testing]

// number of bases along x-axis
gridx = 2;
// number of bases along y-axis
gridy = 2;
// bin height. See bin height information and "gridz_define" below.
gridz = 3;

/* [Covered Bin Features] */
Lid_Fit_Tolerance = 0.1; // [0:0.1:1]
Interior_Style = "minimal"; // [minimal: Minimal, partial_raised: Partially raised]
Lip_Grips = "single"; // [none: None, single: Along X axis, full: Along X and Y axes]

/* [Linear Compartments] */
// number of X Divisions (set to zero to have solid bin)
divx = 6;
// number of Y Divisions (set to zero to have solid bin)
divy = 6;

/* [Height] */
// determine what the variable "gridz" applies to based on your use case
gridz_define = 0; // [0:gridz is the height of bins in units of 7mm increments - Zack's method,1:gridz is the internal height in millimeters, 2:gridz is the overall external height of the bin in millimeters]
// overrides internal block height of bin (for solid containers). Leave zero for default height. Units: mm
height_internal = 0;
// snap gridz height to nearest 7mm increment
enable_zsnap = false;

module __end_customizer_options__() { }

// Constants //

d_wall = 1.60;

lid_wall_thickness = 1.2;
lid_thickness = 0.9;
lid_hfit_tolerance = 0.97;
lid_vfit_tolerance = Lid_Fit_Tolerance;
lid_lip_fit_tolerance = min(0.1, lid_vfit_tolerance);

bin_separator_wall_thickness = 1.2;

module gf_setup_stub(gx, gy, h, h0 = 0, l = l_grid, sl = 0) {
    $gxx = gx;
    $gyy = gy;
    $dh = h;
    $dh0 = h0;
    $style_lip = sl;
    children();
}

module gf_setup() {
    gf_setup_stub(gridx, gridy, height(gridz, gridz_define, 0, enable_zsnap), height_internal)
    children();
}

module gf_profile_wall_lid_lip(lid=false) {
    difference() {
        profile_wall();
        translate([r_base,0,0])
        mirror([1,0,0])
        translate([
            lid ? lid_hfit_tolerance : lid_wall_thickness,
            $dh - lid_thickness - lid_vfit_tolerance
        ])
        polygon([
            [0, 0],
            [0, lid_thickness + lid_vfit_tolerance],
            [d_wall2, lid_thickness + lid_vfit_tolerance + d_wall2],
            [d_wall2, 0],
        ]);
    }
}

module gf_bin_lid_lip_mask() {
    translate([l_grid * gridx - 0.5 - r_base, 0, $dh + h_base - lid_thickness])
    linear_extrude(height=(gridz + 10) * 7)
    square([l_grid * gridx, l_grid * gridy], center=true);
}

module gf_bin_lid_grip_mask_set(num_grid) {
    grip_w = l_grid / 2 - h_lip * 2;
    radius = 3;
    rotate([90, 0, 90])
    translate([0, 0, l_grid * num_grid / 2])
    linear_extrude(height=l_grid / 2, center=true)
    translate([-(grip_w - l_grid / 2) / 2, 0])
    offset(r=radius)
    offset(r=-radius)
    square([grip_w, h_lip * 10]);

}

module gf_bin_lid_grip_mask() {
    if (Lip_Grips != "none")
    translate([0, 0, $dh + h_base + h_lip * 0.25])
    pattern_linear(1, gridy, l_grid * gridx, l_grid)
    gf_bin_lid_grip_mask_set(gridx);
}

module gf_bin_lid_grip_mask_alt() {
    translate([0, 0, $dh + h_base + h_lip * 0.25])
    pattern_linear(gridx, 1, l_grid, l_grid * gridy)
    rotate(90)
    gf_bin_lid_grip_mask_set(gridy);
}


module gf_bin_lid() {
    color("mintcream", 0.5)
    render(convexity=4)
    union() {
        difference() {
            intersection() {
                block_wall(gridx, gridy, l_grid)
                profile_wall();
                gf_bin_lid_lip_mask();
            }
            gf_bin_lid_grip_mask();
        }


        difference() {
            sz = 0.5 + lid_hfit_tolerance * 3;
            union() {
                translate([0, 0, $dh + h_base - lid_thickness])
                gf_bin_rounded_rect(lid_thickness, add_x=-sz, add_y=-sz, r=r_fo1-sz);

                intersection() {
                    translate([0, 0, $dh + h_base - lid_thickness])
                    gf_bin_rounded_rect(h_lip + lid_thickness, add_x=-sz, add_y=-sz, r=r_fo1-sz);

                    block_wall(gridx, gridy, l_grid)
                    difference() {
                        color("yellow", 0.8)
                        profile_wall();
                        union() {
                            color("lightblue", 0.8)
                            square([r_base, $dh]);
                            color("lightgreen", 0.8)
                            translate([r_base - d_wall, 0])
                            square([r_base, $dh + h_lip]);
                        }
                        offset(delta=0.15)
                        gf_profile_wall_lid_lip(lid=true);
                    }
                }
            }

            gf_bin_lid_tabs(adjust=true);
        }
    }
}

module gf_bin_lid_tabs(adjust=false) {
    adj = adjust ? -lid_hfit_tolerance * 1.5 + lid_wall_thickness: 0;
    cr = 0.6;
    // Tabs
    translate([
        -(l_grid * gridx - 0.5) / 2 + r_base + cr,
        0,
        $dh + h_base - lid_thickness - lid_lip_fit_tolerance / 2 - 0.001
    ])
    for (ml = [0, 1])
    mirror([0, ml])
    translate([
        0,
        (
            gridy * l_grid / 2 - 0.5 / 2
            - lid_wall_thickness
            + adj
        ),
        -lid_vfit_tolerance
    ])
    linear_extrude(height=lid_lip_fit_tolerance * 2 + lid_thickness + 2)
    intersection() {
        $fs = $fs / 4;
        offset(r=-(cr * 0.5))
        offset(r=(cr * 0.5))
        union() {
            circle(r=cr);
            translate([0, cr * 4])
            square(cr * 8, center=true);
        }
        square([cr * 3, cr * 2], center=true);
    }
}

module gf_bin_solid() {
    color("darkseagreen", 0.8)
    render(convexity=4)
    gf_setup() {
        render(convexity=4)
        difference() {
            union() {
                block_wall(gridx, gridy, l_grid)
                gf_profile_wall_lid_lip(lid=false);
                gf_bin_lid_tabs();
            }
            translate([-lid_lip_fit_tolerance, 0, -lid_lip_fit_tolerance])
            gf_bin_lid_lip_mask();
            rotate(180)
            gf_bin_lid_grip_mask();
            if (Lip_Grips == "full") {
                for (rot = [0, 180])
                rotate(rot)
                gf_bin_lid_grip_mask_alt();
            }
        }

        render(convexity=4)
        difference() {
            union() {
                block_bottom(
                    ($dh0==0?$dh-0.1:$dh0) - lid_thickness - lid_vfit_tolerance,
                    gridx,
                    gridy,
                    l_grid
                );
                gf_base_grid_interior();
            }
            children();
        }

        render(convexity=4)
        intersection() {
            translate([0, 0, -1])
            gf_bin_rounded_rect(h_base + h_bot / 2 * 10, add_x=-0.5, add_y=-0.5);
            difference() {
                union() {
                    gf_base_grid();
                    translate([0, 0, h_base + h_bot / 2 - d_wall])
                    gf_bin_rounded_rect(d_wall, add_x=-d_wall, add_y=-d_wall);
                }
                intersection() {
                    if (Interior_Style == "partial_raised") {
                        translate([0, 0, d_wall + h_base - r_c2 + 0.1])
                        linear_extrude(height=h_base - r_c2)
                        square([l_grid * gridx, l_grid * gridy], center=true);
                    }
                    gf_base_grid_interior();
                }
            }
        }
    }
}

module gf_base_grid_interior() {
    translate([0, 0, d_wall])
    gf_base_grid(-d_wall);
}

module gf_base_grid(size_offset=0) {
    pattern_linear(gridx, gridy, l_grid, l_grid)
    intersection() {
        block_base_solid(1, 1, l_grid, size_offset);
        linear_extrude(height=h_base + h_bot / 2 + size_offset)
        square([gridx * l_grid, gridy * l_grid], center=true);
    }
}

module gf_bin_rounded_rect(height, add_x=0, add_y=0, r=r_fo1) {
    rounded_rectangle(
        gridx * l_grid + add_x + 0.005,
        gridy * l_grid + add_y + 0.005,
        height,
        r / 2 + 0.001
    );
}

module gf_cut_pockets() {
    if (divx > 0 && divy > 0) {
        per_x = (gridx * l_grid - d_wall * 2 + bin_separator_wall_thickness) / divx;
        per_y = (gridy * l_grid - d_wall * 2 + bin_separator_wall_thickness) / divy;
        cut_move(x=0, y=0, w=gridx, h=gridy)
        pattern_linear(x=divx, y=divy, sx=per_x, sy=per_y)
        translate([0, 0, -$dh - h_base])
        linear_extrude(
            height=gridz * 7 - lid_thickness - lid_vfit_tolerance + 0.001
        )
        square([
            per_x - bin_separator_wall_thickness,
            per_y - bin_separator_wall_thickness,
        ], center=true);
    }
}

module gf_bin(pockets=true) {
    gf_bin_solid()
    if (pockets)
    gf_cut_pockets();
}

module main() {
    if (Part == "bin") {
        gf_bin();
    } else if (Part == "lid") {
        gf_setup() {
            translate([0, 0, -$dh - h_base + lid_thickness])
            gf_bin_lid();
        }
    } else if (Part == "both_closed" || Part == "both_open") {
        // Bin
        gf_bin();
        // Lid
        if ($preview)
        translate([Part == "both_open" ? l_grid * gridx - h_lip * 2 : 0, 0, 0])
        gf_setup()
        gf_bin_lid();
    } else if (Part == "bin_slice") {
        color("darkseagreen", 0.8)
        render()
        intersection() {
            gf_setup() {
                bh = $dh + h_base - lid_thickness * 2;
                translate([0, 0, -bh])
                gf_bin(pockets=false);
            }
            linear_extrude(height=h_lip + 7)
            square([l_grid * gridx, l_grid * gridy], center=true);
        }
    }
}

main();
