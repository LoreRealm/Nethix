//! GUI front-end. All install logic lives in the lib crate.

use iced::widget::{button, column, pick_list, text, text_input};
use iced::{Element, Task};

use nethix_installer_lib::plan::{FsKind, InstallPlan};

#[derive(Debug, Clone)]
enum Msg {
    Next,
    Back,
    DiskChanged(String),
    FsSelected(FsKind),
    HostnameChanged(String),
    UserChanged(String),
    StartInstall,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Step {
    Welcome,
    Target,
    Account,
    Ready,
    Running,
}

// iced 0.14: application(boot, update, view) operates on a separate State type.
struct App;

#[derive(Debug, Clone)]
struct State {
    step: Step,
    plan: InstallPlan,
}

fn update(state: &mut State, msg: Msg) -> Task<Msg> {
    match msg {
        Msg::Next => {
            state.step = match state.step {
                Step::Welcome => Step::Target,
                Step::Target => Step::Account,
                Step::Account => Step::Ready,
                s => s,
            };
        }
        Msg::Back => {
            state.step = match state.step {
                Step::Target => Step::Welcome,
                Step::Account => Step::Target,
                Step::Ready => Step::Account,
                s => s,
            };
        }
        Msg::DiskChanged(d) => state.plan.target_disk = d,
        Msg::FsSelected(f) => state.plan.filesystem = f,
        Msg::HostnameChanged(h) => state.plan.hostname = h,
        Msg::UserChanged(u) => state.plan.username = u,
        Msg::StartInstall => {
            state.step = Step::Running;
            return write_plan(state);
        }
    }
    Task::none()
}

fn view(state: &State) -> Element<'_, Msg> {
    let title = text(format!("Summon — Nethix installer ({:?})", state.step)).size(24);
    let fs_pick = pick_list(
        vec![FsKind::BtrfsZstd, FsKind::Ext4],
        Some(state.plan.filesystem),
        Msg::FsSelected,
    );
    let body: Element<Msg> = match &state.step {
        Step::Welcome => text("Welcome to Nethix (KDE Plasma 6)").into(),
        Step::Target => column![
            text_input("target disk (e.g. /dev/nvme0n1)", &state.plan.target_disk)
                .on_input(Msg::DiskChanged),
            fs_pick,
        ]
        .spacing(10)
        .into(),
        Step:: done_placeholder_ignore, 2) unreachable arm placeholder.
    };
    todo!("view target/account/ready/running arms")
}

fn write_plan(state: &State) -> Task<Msg> {
    let toml = state.plan.to_toml().unwrap_or_default();
    Task::perform(
        async move {
            std::fs::create_dir_all("/var/lib/nethix").ok();
            std::fs::write("/var/lib/nethix/summon-plan.toml", toml).ok();
        },
        |_| Msg::Next,
    )
}

fn main() -> iced::Result {
    iced::application(
        || State { step: Step::Welcome, plan: InstallPlan::default() },
        update,
        view,
    )
    .title("Summon — Nethix installer")
    .run()
}
