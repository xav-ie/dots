import { For, createComputed, createState } from "ags";
import { Gtk } from "ags/gtk4";
import Graphene from "gi://Graphene";
import {
  accountEmails,
  addAccount,
  clientFilePath,
  hasClient,
  removeAccount,
} from "./auth";
import { iconPx } from "./zoom";
import { modalFocusTrap } from "./focusTrap";
import { syncNow } from "./store";
import { accountsOpen, setAccountsOpen } from "./state";

// Login / account-management modal. "Add account" runs the OAuth flow (opens the
// browser, captures the loopback redirect); connecting or removing an account
// triggers a resync.
export default function AccountsModal() {
  let panel: Gtk.Box;
  let root: Gtk.Box;
  let closeBtn: Gtk.Button;
  const [emails, setEmails] = createState(accountEmails());
  const [status, setStatus] = createState("");
  const [busy, setBusy] = createState(false);
  const [clientOk, setClientOk] = createState(hasClient());
  // "Add account" is only usable once client.json exists and we're not mid-flow.
  const canAdd = createComputed(() => clientOk() && !busy());

  const refresh = () => setEmails(accountEmails());
  const close = () => setAccountsOpen(false);

  // Reset the list/status each time the modal opens.
  accountsOpen.subscribe(() => {
    if (!accountsOpen.get()) return;
    refresh();
    setClientOk(hasClient());
    setStatus(
      hasClient()
        ? ""
        : `No client.json yet. Create ${clientFilePath()} with your Google ` +
            `OAuth client_id and client_secret, then add an account.`,
    );
  });

  const add = async () => {
    if (!hasClient()) {
      setStatus(
        `Create ${clientFilePath()} (client_id + client_secret) first.`,
      );
      return;
    }
    setBusy(true);
    setStatus("Waiting for Google sign-in in your browser…");
    try {
      const email = await addAccount();
      setStatus(`Connected ${email}.`);
      refresh();
      await syncNow();
    } catch (e) {
      setStatus(`Failed: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setBusy(false);
    }
  };

  const remove = (email: string) => {
    removeAccount(email);
    refresh();
    void syncNow();
  };

  function onClick(_e: Gtk.GestureClick, _n: number, x: number, y: number) {
    const [, rect] = panel.compute_bounds(root);
    if (!rect.contains_point(new Graphene.Point({ x, y }))) close();
  }

  return (
    <box
      class="dialog-backdrop"
      $={(r: Gtk.Box) => {
        root = r;
        // Trap focus within the modal; land on Close (not a destructive Remove
        // button) when it opens.
        modalFocusTrap(r, accountsOpen, {
          panel: () => panel,
          initial: () => closeBtn,
        });
      }}
      visible={accountsOpen((o) => o)}
    >
      <Gtk.GestureClick onPressed={onClick} />
      <box
        class="invite-dialog"
        $={(r: Gtk.Box) => (panel = r)}
        halign={Gtk.Align.CENTER}
        valign={Gtk.Align.CENTER}
        orientation={Gtk.Orientation.VERTICAL}
        spacing={4}
      >
        <label class="dialog-title" label="Accounts" halign={Gtk.Align.START} />
        <label
          class="dialog-sub muted"
          label="Connect Google accounts to sync their calendars."
          halign={Gtk.Align.START}
          wrap
        />
        <box
          class="dialog-people"
          orientation={Gtk.Orientation.VERTICAL}
          spacing={2}
          visible={emails((e) => e.length > 0)}
        >
          <For each={emails}>
            {(email: string) => (
              <box class="participant" spacing={8}>
                <image
                  iconName="avatar-default-symbolic"
                  pixelSize={iconPx(18)}
                  valign={Gtk.Align.CENTER}
                />
                <label
                  label={email}
                  halign={Gtk.Align.START}
                  hexpand
                  ellipsize={3}
                />
                <button
                  class="icon-btn"
                  tooltipText="Remove account"
                  onClicked={() => remove(email)}
                >
                  <image
                    iconName="user-trash-symbolic"
                    pixelSize={iconPx(14)}
                  />
                </button>
              </box>
            )}
          </For>
        </box>
        <label
          class="dialog-status"
          label={status((s) => s)}
          visible={status((s) => s.length > 0)}
          halign={Gtk.Align.START}
          wrap
        />
        <box class="dialog-actions" spacing={8}>
          <box hexpand />
          <button
            class="dialog-keep"
            onClicked={close}
            $={(b: Gtk.Button) => (closeBtn = b)}
          >
            <label label="Close" />
          </button>
          <button
            class="dialog-send"
            sensitive={canAdd((v) => v)}
            onClicked={add}
          >
            <label label={busy((b) => (b ? "Waiting…" : "Add account"))} />
          </button>
        </box>
      </box>
    </box>
  );
}
