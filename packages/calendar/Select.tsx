import { createState } from "ags";
import { Gtk } from "ags/gtk4";
import { iconPx } from "./zoom";

const START = Gtk.Align.START;

// Shared value dropdown: a menubutton trigger + a popover list with a checkmark
// on the active option. Used by the editor's inline selects (Busy/Free,
// visibility, …) for consistency.
export default function Select(props: {
  value: string;
  options: string[];
  onChange?: (v: string) => void;
  class?: string;
}) {
  const [cur, setCur] = createState(props.value);
  let pop: Gtk.Popover;
  return (
    <menubutton class={`select ${props.class ?? ""}`}>
      <box spacing={6}>
        <label
          class="select-label"
          label={cur((c) => c)}
          halign={START}
          hexpand
        />
        <image iconName="pan-down-symbolic" pixelSize={iconPx(11)} />
      </box>
      <popover class="select-pop" $={(p: Gtk.Popover) => (pop = p)}>
        <box class="select-menu" orientation={Gtk.Orientation.VERTICAL}>
          {props.options.map((o) => (
            <button
              class="select-item"
              onClicked={() => {
                // Skip re-picking the active option so an unchanged "edit"
                // doesn't pop the recurring scope dialog.
                if (o !== cur.get()) {
                  setCur(o);
                  props.onChange?.(o);
                }
                pop.popdown();
              }}
            >
              <box spacing={8}>
                <box class="select-check">
                  <image
                    iconName="object-select-symbolic"
                    pixelSize={iconPx(12)}
                    visible={cur((c) => c === o)}
                  />
                </box>
                <label label={o} halign={START} hexpand />
              </box>
            </button>
          ))}
        </box>
      </popover>
    </menubutton>
  );
}
