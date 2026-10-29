use eframe::egui::{self, Color32, RichText};

pub fn main_view(ui: &mut egui::Ui, selected: usize) {
    egui::Frame::central_panel(ui.style()).show(ui, |ui| {
        ui.horizontal(|ui| {
            ui.heading("Shortcut Palette");
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.label(RichText::new("72 ENTRIES").small());
            });
        });
        ui.add_space(8.0);
        egui::Frame::group(ui.style())
            .inner_margin(10.0)
            .show(ui, |ui| {
                ui.label("Search shortcuts, commands, facets, and object memory");
                ui.small("Static benchmark corpus · selection drives the auxiliary canvas");
            });
        ui.add_space(8.0);

        let sections = ["Focus", "Move", "Stack", "Layout", "Workspace", "System"];
        egui::ScrollArea::vertical().show(ui, |ui| {
            for index in 0..72 {
                let fill = if selected == index {
                    Color32::from_rgb(42, 62, 86)
                } else {
                    Color32::TRANSPARENT
                };
                egui::Frame::new()
                    .fill(fill)
                    .inner_margin(8.0)
                    .show(ui, |ui| {
                        ui.set_min_height(28.0);
                        ui.horizontal(|ui| {
                            let marker = if selected == index { "▶" } else { " " };
                            ui.add_sized(
                                [132.0, 20.0],
                                egui::Label::new(format!(
                                    "{marker}  u{}+{}",
                                    index % 3,
                                    (b'a' + (index % 26) as u8) as char
                                )),
                            );
                            ui.label(format!("Representative shortcut action {:02}", index + 1));
                            ui.with_layout(
                                egui::Layout::right_to_left(egui::Align::Center),
                                |ui| {
                                    ui.small(sections[index % sections.len()]);
                                },
                            );
                        });
                    });
            }
        });
    });
}

pub fn auxiliary_view(ui: &mut egui::Ui, selected: usize) {
    egui::Frame::central_panel(ui.style()).show(ui, |ui| {
        egui::Frame::group(ui.style()).inner_margin(15.0).show(ui, |ui| {
            ui.small("Object Memory Preview");
            ui.heading(format!(
                "Selected action {}: move, focus, or transform the active object",
                selected + 1
            ));
            ui.small("Representative defining expression, scenario annotation, availability note, source path, and extended explanation.");
        });
        ui.add_space(16.0);
        ui.columns(2, |columns| {
            columns[0].set_min_width(850.0);
            columns[0].heading("Binding Atlas · modifier plane and related bindings");
            columns[0].add_space(12.0);
            egui::Grid::new("binding-atlas")
                .spacing([8.0, 8.0])
                .show(&mut columns[0], |ui| {
                    for row in 0..6 {
                        for column in 0..11 {
                            let index = row * 11 + column;
                            let label = if index < 26 {
                                ((b'A' + index as u8) as char).to_string()
                            } else {
                                format!("K{:02}", index + 1)
                            };
                            let marker = if selected % 66 == index { "●" } else { " " };
                            ui.add_sized([64.0, 42.0], egui::Button::new(format!("{marker} {label}")));
                        }
                        ui.end_row();
                    }
                });

            side_panel(&mut columns[1], "Navigation", |ui| {
                ui.heading("H  J  K  L");
                ui.small("word · line · page · history");
                ui.small(format!("selected relation {}", selected % 12));
            });
            side_panel(&mut columns[1], "Numpad / Operations", |ui| {
                ui.label("7   8   9   +");
                ui.label("4   5   6   -");
                ui.label("1   2   3   Enter");
            });
            side_panel(&mut columns[1], "Dossier", |ui| {
                ui.small("Provider       kanata");
                ui.small("Family         komorebi");
                ui.small("Target         window");
                ui.small("Applicability  available");
                ui.small(format!("Generation     {selected}"));
            });
        });
    });
}

fn side_panel(ui: &mut egui::Ui, title: &str, content: impl FnOnce(&mut egui::Ui)) {
    egui::Frame::group(ui.style())
        .inner_margin(14.0)
        .show(ui, |ui| {
            ui.strong(title);
            ui.add_space(5.0);
            content(ui);
            ui.set_min_height(130.0);
        });
    ui.add_space(12.0);
}
