//! Spire — app store GUI for Nethix.
//! Browses flatpaks (FlatpakBackend) and AUR packages (ScriBackend)
//! through one unified interface.

mod backend;

use backend::{store_backend, Backend, Listing};
use iced::widget::{button, column, scrollable, text, text_input};
use iced::{Element, Task};

#[derive(Debug, Clone)]
enum Msg {
    QueryChanged(String),
    Search,
    Results(Vec<Listing>),
    Failed(String),
    Install(String),
    Installed(String, bool),
    BackendChanged(backend::Kind),
}

#[derive(Debug, Clone)]
struct State {
    backend_kind: backend::Kind,
    query: String,
    listings: Vec<Listing>,
    status: Option<String>,
    busy: bool,
}

fn update(state: &mut State, msg: Msg) -> Task<Msg> {
    match msg {
        Msg::QueryChanged(q) => {
            state.query = q;
            Task::none()
        }
        Msg::BackendChanged(k) => {
            state.backend_kind = k;
            state.listings.clear();
            state.status = None;
            Task::none()
        }
        Msg::Search => {
            if state.query.trim().is_empty() {
                return Task::none();
            }
            state.busy = true;
            let q = state.query.trim().to_string();
            let kind = state.backend_kind;
            Task::perform(
                async move {
                    let b = store_backend(kind);
                    b.search(&q).await.map_err(|e| e.to_string())
                },
                |res| match res {
                    Ok(l) => Msg::Results(l),
                    Err(e) => Msg::Failed(e),
                },
            )
        }
        Msg::Results(mut l) => {
            l.sort_by(|a, b| b.popularity.cmp(&a.popularity));
            state.listings = l;
            state.busy = false;
            state.status = None;
            Task::none()
        }
        Msg::Failed(e) => {
            state.status = Some(format!("search failed: {e}"));
            state.busy = false;
            Task::none()
        }
        Msg::Install(id) => {
            state.busy = true;
            let kind = state.backend_kind;
            Task::perform(
                async move {
                    let b = store_backend(kind);
                    b.install(&id).await.map_err(|e| e.to_string()).map(|_| id.clone())
                },
                |res| match res {
                    Ok(id) => Msg::Installed(id, true),
                    Err(e) => Msg::Installed(e, false),
                },
            )
        }
        Msg::Installed(msg, ok) => {
            state.busy = false;
            state.status = Some(if ok {
                format!("installed: {msg}")
            } else {
                format!("install failed: {msg}")
            });
            Task::none()
        }
    }
}

fn view(state: &State) -> Element<'_, Msg> {
    let title = text("Spire — the App Store for Nethix").size(24);
    let tabs = iced::widget::row(
        [backend::Kind::Aur, backend::Kind::Flatpak]
            .iter()
            .map(|k| {
                let b = store_backend(*k);
                button(text(format!("{}", b.name())))
                    .on_press_maybe(Some(Msg::BackendChanged(*k)))
            })
            .collect(),
    )
    .spacing(8);

    let search_row = iced::widget::row![
        text_input("search packages...", &state.query).on_input(Msg::QueryChanged),
        button("Search").on_press(Msg::Search),
    ]
    .spacing(8);

    let mut list_col = column().spacing(4);
    for l in &state.listings {
        list_col = list_col.push(
            iced::widget::column![
                text(format!("{} — {}", l.name, l.summary)).size(14),
                iced::widget::row![
                    text(format!("popularity: {}", l.popularity)).size(11),
                    match &l.risk_note {
                        Some(note) => text(format!("risk: {note}")).size(11),
                        None => text("").size(11),
                    },
                    button("Install").on_press(Msg::Install(l.id.clone())),
                ]
                .spacing(12),
            ]
            .padding(4),
        );
    }

    let body = column![
        title,
        tabs,
        search_row,
        match &state.status {
            Some(s) => text(s.clone()),
            None => text(""),
        },
        scrollable(list_col),
    ]
    .padding(20)
    .spacing(12);

    body.into()
}

fn main() -> iced::Result {
    iced::application(
        || State {
            backend_kind: backend::Kind::Aur,
            query: String::new(),
            listings: Vec::new(),
            status: None,
            busy: false,
        },
        update,
        view,
    )
    .title("Spire")
    .run()
}
