use iced::widget::{Column, Row, Space, column, container, row, scrollable, text};
use iced::{Element, Length};

use crate::controller::Message;

pub fn main_view(selected: usize) -> Element<'static, Message> {
    let header = row![
        text("Shortcut Palette").size(25),
        Space::new().width(Length::Fill),
        container(text("72 ENTRIES").size(11)).padding([7, 14]),
    ]
    .align_y(iced::Alignment::Center);

    let search = column![
        text("Search shortcuts, commands, facets, and object memory").size(15),
        text("Static benchmark corpus · selection drives the auxiliary canvas").size(11),
    ]
    .spacing(3);

    let sections = ["Focus", "Move", "Stack", "Layout", "Workspace", "System"];
    let mut entries = Column::new().spacing(2);
    for index in 0..72 {
        let marker = if selected == index { "▶" } else { " " };
        entries = entries.push(
            container(
                row![
                    text(format!(
                        "{marker}  u{}+{}",
                        index % 3,
                        (b'a' + (index % 26) as u8) as char
                    ))
                    .width(Length::Fixed(132.0)),
                    text(format!("Representative shortcut action {:02}", index + 1))
                        .width(Length::Fill),
                    text(sections[index % sections.len()]).size(12),
                ]
                .align_y(iced::Alignment::Center),
            )
            .height(44)
            .padding([0, 12]),
        );
    }

    container(
        column![
            header,
            container(search).padding([10, 15]),
            scrollable(entries)
        ]
        .spacing(12)
        .padding(18),
    )
    .width(Length::Fill)
    .height(Length::Fill)
    .into()
}

pub fn auxiliary_view(selected: usize) -> Element<'static, Message> {
    let preview = container(
        column![
            text("Object Memory Preview").size(13),
            text(format!(
                "Selected action {}: move, focus, or transform the active object",
                selected + 1
            ))
            .size(18),
            text("Representative defining expression, scenario annotation, availability note, source path, and extended explanation.").size(12),
        ]
        .spacing(7),
    )
    .padding([15, 20])
    .height(114);

    let mut key_rows = Column::new().spacing(8);
    for row_index in 0..6 {
        let mut keys = Row::new().spacing(8);
        for column_index in 0..11 {
            let index = row_index * 11 + column_index;
            let label = if index < 26 {
                ((b'A' + index as u8) as char).to_string()
            } else {
                format!("K{:02}", index + 1)
            };
            let marker = if selected % 66 == index { "●" } else { " " };
            keys = keys.push(
                container(text(format!("{marker} {label}")).size(12))
                    .width(64)
                    .height(42)
                    .center_x(Length::Fill)
                    .center_y(Length::Fill),
            );
        }
        key_rows = key_rows.push(keys);
    }

    let atlas = container(
        column![
            text("Binding Atlas · modifier plane and related bindings").size(16),
            key_rows
        ]
        .spacing(16),
    )
    .padding([17, 21])
    .width(854)
    .height(Length::Fill);

    let side = column![
        panel(column![
            text("Navigation").size(14),
            text("H  J  K  L").size(21),
            text("word · line · page · history").size(12),
            text(format!("selected relation {}", selected % 12)).size(12),
        ]),
        panel(column![
            text("Numpad / Operations").size(14),
            text("7   8   9   +").size(18),
            text("4   5   6   -").size(18),
            text("1   2   3   Enter").size(18),
        ]),
        panel(column![
            text("Dossier").size(14),
            text("Provider       kanata").size(12),
            text("Family         komorebi").size(12),
            text("Target         window").size(12),
            text("Applicability  available").size(12),
            text(format!("Generation     {selected}")).size(12),
        ]),
    ]
    .spacing(18)
    .width(266);

    container(
        column![preview, row![atlas, side].spacing(18)]
            .spacing(18)
            .padding([22, 24]),
    )
    .width(Length::Fill)
    .height(Length::Fill)
    .into()
}

fn panel(content: Column<'static, Message>) -> Element<'static, Message> {
    container(content.spacing(8))
        .padding([14, 17])
        .width(266)
        .height(172)
        .into()
}
