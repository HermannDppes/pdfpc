/**
 * Presentater window
 *
 * This file is part of pdfpc.
 *
 * Copyright (C) 2010-2011 Jakob Westhoff <jakob@westhoffswelt.de>
 * Copyright 2011-2012 David Vilar
 * Copyright 2012, 2015 Robert Schroll
 * Copyright 2012, 2015, 2017 Andreas Bilke
 * Copyright 2013 Gabor Adam Toth
 * Copyright 2015-2016 Andy Barry
 * Copyright 2015 Jeremy Maitin-Shepard
 * Copyright 2017 Olivier Pantalé
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

namespace pdfpc.Window {
    /**
     * Window showing the currently active and next slide.
     *
     * Other useful information like time slide count, ... can be displayed here as
     * well.
     */
    public class Presenter : Fullscreen, Controllable {
        /**
         * The registered PresentationController
         */
        public PresentationController presentation_controller { get; protected set; }

        /**
         * Only handle links and annotations on the current_view
         */
        public View.Pdf main_view {
            get {
                return this.current_view;
            }
        }

        /**
         * View showing the current slide
         */
        public View.Pdf current_view;

        /**
         * View showing a preview of the next slide
         */
        protected View.Pdf next_view;

        /**
         * View showing the final version of the current user slide
         */
        protected View.Pdf final_view;

        /**
         * Timer for the presenation
         */
        protected TimerLabel? timer;

        /**
         * Slide progress label ( eg. "23/42" )
         */
        protected Gtk.Entry slide_progress;

        protected Gtk.ProgressBar prerender_progress;

        /**
         * Indication that the slide is blanked (faded to black)
         */
        protected Gtk.Image blank_icon;

        /**
         * Indication that the presentation display is frozen
         */
        protected Gtk.Image frozen_icon;

        /**
         * Indication that the timer is paused
         */
        protected Gtk.Image pause_icon;

        /**
         * Indication that the slide is saved
         */
        protected Gtk.Image saved_icon;

        /**
         * Indication that the slide position has been loaded
         */
        protected Gtk.Image loaded_icon;

        /**
         * The overview of slides
         */
        protected Overview overview = null;

        /**
         * The Stack containing the slides view and the overview.
         */
        protected Gtk.Stack slide_stack;

        /**
         * Metadata of the slides
         */
        protected Metadata.Pdf metadata;

        /**
         * Width of future area
         **/
        protected int future_allocated_width;

        /**
         * Base constructor instantiating a new presenter window
         */
        public Presenter(Metadata.Pdf metadata, int screen_num,
            PresentationController presentation_controller) {
            base(screen_num);
            this.role = "presenter";
            this.title = "pdfpc - presenter (%s)".printf(metadata.get_document().get_title());

            this.destroy.connect((source) => presentation_controller.quit());

            this.presentation_controller = presentation_controller;
            this.presentation_controller.update_request.connect(this.update);
            this.presentation_controller.ask_goto_page_request.connect(this.ask_goto_page);
            this.presentation_controller.show_overview_request.connect(this.show_overview);
            this.presentation_controller.hide_overview_request.connect(this.hide_overview);
            this.presentation_controller.increase_font_size_request.connect(this.increase_font_size);
            this.presentation_controller.decrease_font_size_request.connect(this.decrease_font_size);

            this.metadata = metadata;

            // We need the value of 90% height a lot of times. Therefore store it
            // in advance
            var bottom_position = (int) Math.floor(this.screen_geometry.height * 0.9);
            var bottom_height = this.screen_geometry.height - bottom_position;

            // In most scenarios the current slide is displayed bigger than the
            // next one. The option current_size represents the width this view
            // should use as a percentage value. The maximal height is 90% of
            // the screen, as we need a place to display the timer and slide
            // count.
            Gdk.Rectangle current_scale_rect;
            int current_allocated_width = (int) Math.floor(
                this.screen_geometry.width * Options.current_size / (double) 100);
            this.current_view = new View.Pdf.from_metadata(
                metadata,
                current_allocated_width,
                (int) Math.floor(Options.current_height * bottom_position / (double) 100),
                Metadata.Area.NOTES,
                Options.black_on_end,
                true,
                this.presentation_controller,
                this.gdk_scale,
                out current_scale_rect
            );

            // The next slide is right to the current one and takes up the
            // remaining width

            // do not allocate negative width (in case of current_allocated_width == this.screen_geometry.width)
            // this happens, when the user set -u 100
            int future_allocated_width = (int)Math.fmax(this.screen_geometry.width - current_allocated_width - 4, 0);
            this.future_allocated_width = future_allocated_width;
            // We leave a bit of margin between the two views
            Gdk.Rectangle next_scale_rect;

            uint next_height  = Options.next_height;
            uint final_height = Options.final_height;
            uint total_height = next_height + final_height;

            if (total_height > 100) {
                next_height  /= total_height;
                final_height /= total_height;
            };

            this.next_view = new View.Pdf.from_metadata(
                metadata,
                future_allocated_width,
                (int) Math.floor(next_height * bottom_position / (double) 100),
                Metadata.Area.CONTENT,
                true,
                false,
                this.presentation_controller,
                this.gdk_scale,
                out next_scale_rect
            );

            this.final_view = new View.Pdf.from_metadata(
                metadata,
                future_allocated_width,
                (int) Math.floor(final_height * bottom_position / (double) 100),
                Metadata.Area.CONTENT,
                true,
                false,
                this.presentation_controller,
                this.gdk_scale,
                out next_scale_rect
            );


            // The countdown timer is centered in the 90% bottom part of the screen
            this.timer = this.presentation_controller.getTimer();
            this.timer.name = "timer";
            this.timer.get_style_context().add_class("bottomText");
            this.timer.set_justify(Gtk.Justification.CENTER);


            // The slide counter is centered in the 90% bottom part of the screen
            this.slide_progress = new Gtk.Entry();
            this.slide_progress.name = "slideProgress";
            this.slide_progress.get_style_context().add_class("bottomText");
            this.slide_progress.set_alignment(1f);
            this.slide_progress.sensitive = false;
            this.slide_progress.has_frame = false;
            this.slide_progress.key_press_event.connect(this.on_key_press_slide_progress);
            this.slide_progress.valign = Gtk.Align.END;
            // reduce the width of Gtk.Entry. we reserve a width for
            // 7 chars (i.e. maximal 999/999 for displaying)
            this.slide_progress.width_chars = 7;

            this.prerender_progress = new Gtk.ProgressBar();
            this.prerender_progress.name = "prerenderProgress";
            this.prerender_progress.show_text = true;

            // Don't display prerendering text if the user has disabled
            // it, but still create the control to ensure the layout
            // doesn't change.
            if (Options.disable_caching) {
                this.prerender_progress.text = "";
            } else {
                this.prerender_progress.text = "Prerendering...";
            }
            this.prerender_progress.set_ellipsize(Pango.EllipsizeMode.END);
            this.prerender_progress.no_show_all = true;
            this.prerender_progress.valign = Gtk.Align.END;

            int icon_height = (int)Math.round(bottom_height*0.9);;

            this.blank_icon = this.load_icon("blank.svg", icon_height);
            this.frozen_icon = this.load_icon("snow.svg", icon_height);
            this.pause_icon = this.load_icon("pause.svg", icon_height);
            this.saved_icon = this.load_icon("saved.svg", icon_height);
            this.loaded_icon = this.load_icon("loaded.svg", icon_height);

            this.add_events(Gdk.EventMask.KEY_PRESS_MASK);
            this.add_events(Gdk.EventMask.BUTTON_PRESS_MASK);
            this.add_events(Gdk.EventMask.SCROLL_MASK);

            this.key_press_event.connect(this.presentation_controller.key_press);
            this.button_press_event.connect(this.presentation_controller.button_press);
            this.scroll_event.connect(this.presentation_controller.scroll);

            // resize the bottom text based on the window height
            // (see http://stackoverflow.com/a/35237445/730138)
            var bottom_text_css_provider = new Gtk.CssProvider();
            Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(),
                bottom_text_css_provider, Gtk.STYLE_PROVIDER_PRIORITY_FALLBACK);

            const string bottom_text_css_template = ".bottomText { font-size: %dpx; }";
            var target_size_height = (int) ((double)this.screen_geometry.height / 400.0 * 12.0);
            var bottom_css = bottom_text_css_template.printf(target_size_height);

            try {
                bottom_text_css_provider.load_from_data(bottom_css, -1);
            } catch (Error e) {
                GLib.printerr("Warning: failed to set CSS for auto-sized bottom controls.\n");
            }

            this.overview = new Overview(this.metadata, this.presentation_controller, this);
            this.overview.vexpand = true;
            this.overview.hexpand = true;
            this.overview.set_n_slides(this.presentation_controller.user_n_slides);
            this.presentation_controller.set_overview(this.overview);
            this.presentation_controller.register_controllable(this);

            // Enable the render caching if it hasn't been forcefully disabled.
            if (!Options.disable_caching) {
                this.current_view.get_renderer().cache = Renderer.Cache.create(metadata);
                this.next_view.get_renderer().cache = Renderer.Cache.create(metadata);
                this.final_view.get_renderer().cache = Renderer.Cache.create(metadata);
            }

            Gtk.Box slide_views = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);

            this.current_view.halign = Gtk.Align.CENTER;
            this.current_view.valign = Gtk.Align.CENTER;

            fixed_layout.put(current_view, 0, 0);

            slide_views.pack_start(fixed_layout, true, true, 0);

            var futureViews = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            futureViews.set_size_request(this.future_allocated_width, -1);

            this.next_view.halign = Gtk.Align.CENTER;
            this.next_view.valign = Gtk.Align.START;
            futureViews.pack_start(next_view, true, false, 0);

            this.final_view.halign = Gtk.Align.CENTER;
            this.final_view.valign = Gtk.Align.END;
            futureViews.pack_start(final_view, true, false, 0);

            slide_views.pack_start(futureViews, true, true, 0);

            this.slide_stack = new Gtk.Stack();
            this.slide_stack.add_named(slide_views, "slides");
            this.slide_stack.add_named(this.overview, "overview");
            this.slide_stack.homogeneous = true;

            var bottom_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            bottom_row.set_size_request(this.screen_geometry.width, bottom_height);
            bottom_row.homogeneous = true;

            var status = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 2);
            status.pack_start(this.blank_icon, false, false, 0);
            status.pack_start(this.frozen_icon, false, false, 0);
            status.pack_start(this.pause_icon, false, false, 0);
            status.pack_start(this.saved_icon, false, false, 0);
            status.pack_start(this.loaded_icon, false, false, 0);

            this.timer.halign = Gtk.Align.CENTER;
            this.timer.valign = Gtk.Align.END;

            var progress_alignment = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            progress_alignment.pack_start(this.prerender_progress);
            progress_alignment.pack_end(this.slide_progress, false);

            bottom_row.pack_start(status);
            bottom_row.pack_start(this.timer);
            bottom_row.pack_end(progress_alignment);

            Gtk.Box full_layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            full_layout.set_size_request(this.screen_geometry.width, this.screen_geometry.height);
            full_layout.pack_start(this.slide_stack, true, true, 0);
            full_layout.pack_end(bottom_row, false, false, 0);

            this.add(full_layout);
        }

        public override void show() {
            base.show();
            Gtk.Allocation allocation;
            this.get_allocation(out allocation);
            this.overview.set_available_space(allocation.width,
                (int) Math.floor(allocation.height * 0.9));
        }

        protected Gtk.Image load_icon(string filename, int icon_height) {

            // attempt to load from a local path (if the user hasn't installed)
            // if that fails, attempt to load from the global path
            string load_icon_path = Path.build_filename(Paths.SOURCE_PATH, "icons", filename);
            File icon_file = File.new_for_path(load_icon_path);
            if (!icon_file.query_exists()) {
                load_icon_path = Path.build_filename(Paths.ICON_PATH, filename);
            }

            Gtk.Image icon;
            try {
                int width = (int) Math.floor(1.06 * icon_height) * this.gdk_scale;
                int height = icon_height * this.gdk_scale;

                Gdk.Pixbuf pixbuf = new Gdk.Pixbuf.from_file_at_size(load_icon_path, width, height);
                Cairo.Surface surface = Gdk.cairo_surface_create_from_pixbuf(pixbuf, 0, null);

                icon = new Gtk.Image.from_surface(surface);
                icon.no_show_all = true;
            } catch (Error e) {
                GLib.printerr("Warning: Could not load icon %s (%s)\n", load_icon_path, e.message);
                icon = new Gtk.Image.from_icon_name("image-missing", Gtk.IconSize.LARGE_TOOLBAR);
            }
            return icon;
        }

        public void session_saved() {
            this.saved_icon.show();
        }

        public void session_loaded() {
            this.loaded_icon.show();
        }

        /**
         * Update the slide count view
         */
        protected void update_slide_count() {
            this.custom_slide_count(this.metadata.real_slide_to_user_slide(this.presentation_controller.current_slide_number) + 1);
        }

        public void custom_slide_count(int current) {
            int total = this.presentation_controller.get_end_user_slide();
            this.slide_progress.set_text("%d/%u".printf(current, total));
        }

        public void update() {
            int current_slide_number = this.presentation_controller.current_slide_number;
            int current_user_slide_number = this.presentation_controller.current_user_slide_number;
            try {
                this.current_view.display(current_slide_number);
                this.next_view.display(this.metadata.user_slide_to_real_slide(
                    current_user_slide_number + 1));
                if (this.presentation_controller.skip_next()) {
                    this.final_view.display(
                        this.metadata.user_slide_to_real_slide(
                            current_user_slide_number),
                        // Force redraw
                        true);
                } else {
                    this.final_view.fade_to_black();
                }
            }
            catch( Renderer.RenderError e ) {
                GLib.printerr("The pdf page %d could not be rendered: %s\n", current_slide_number, e.message);
                Process.exit(1);
            }
            this.update_slide_count();
            if (this.timer.is_paused())
                this.pause_icon.show();
            else
                this.pause_icon.hide();
            if (this.presentation_controller.faded_to_black)
                this.blank_icon.show();
            else
                this.blank_icon.hide();
            if (this.presentation_controller.frozen)
                this.frozen_icon.show();
            else
                this.frozen_icon.hide();
            this.faded_to_black = false;
 	    this.saved_icon.hide();
 	    this.loaded_icon.hide();
        }

        /**
         * Display a specific page
         */
        public void goto_page(int page_number) {
            try {
                this.current_view.display(page_number);
                this.next_view.display(page_number + 1);
            } catch( Renderer.RenderError e ) {
                GLib.printerr("The pdf page %d could not be rendered: %s\n", page_number, e.message);
                Process.exit(1);
            }

            this.update_slide_count();
            this.blank_icon.hide();
        }

        /**
         * Ask for the page to jump to
         */
        public void ask_goto_page() {
            this.slide_progress.set_text("/%u".printf(this.presentation_controller.user_n_slides));
            this.slide_progress.sensitive = true;
            this.slide_progress.grab_focus();
            this.slide_progress.set_position(0);
            this.presentation_controller.set_ignore_input_events(true);
        }

        /**
         * Handle key events for the slide_progress entry field
         */
        protected bool on_key_press_slide_progress(Gtk.Widget source, Gdk.EventKey key) {
            if (key.keyval == Gdk.Key.Return) {
                // Try to parse the input
                string input_text = this.slide_progress.text;
                int destination = int.parse(input_text.substring(0, input_text.index_of("/")));
                this.slide_progress.sensitive = false;
                this.presentation_controller.set_ignore_input_events(false);
                if (destination != 0)
                    this.presentation_controller.goto_user_page(destination);
                else
                    this.update_slide_count(); // Reset the display we had before
                return true;
            } else {
                return false;
            }
        }

        public void show_overview() {
            this.overview.current_slide = this.presentation_controller.current_user_slide_number;
            this.slide_stack.set_visible_child_name("overview");
            this.overview.ensure_focus();
        }

        public void hide_overview() {
            this.slide_stack.set_visible_child_name("slides");
            this.overview.ensure_structure();
        }

        /**
         * Take a cache observer and register it with all prerendering Views
         * shown on the window.
         *
         * Furthermore it is taken care of to add the cache observer to this window
         * for display, as it is a Image widget after all.
         */
        public void set_cache_observer(CacheStatus observer) {
            observer.monitor_view(this.current_view);
            observer.monitor_view(this.next_view);
            observer.monitor_view(this.final_view);

            observer.update_progress.connect(this.prerender_progress.set_fraction);
            observer.update_complete.connect(this.prerender_finished);
            this.prerender_progress.show();
        }

        public void prerender_finished() {
            this.prerender_progress.opacity = 0;  // hide() causes a flash for re-layout.
            this.overview.set_cache(this.next_view.get_renderer().cache);
        }

        /**
         * Increase font sizes for Widgets
         */
        public void increase_font_size() {
            int old_font_size = this.metadata.font_size;

            int font_size = (int)(old_font_size*1.1);
            this.metadata.font_size = font_size;
        }

        /**
         * Decrease font sizes for Widgets
         */
        public void decrease_font_size() {
            int old_font_size = this.metadata.font_size;

            int font_size = (int)(old_font_size/1.1);
            this.metadata.font_size = font_size;
        }
    }
}
