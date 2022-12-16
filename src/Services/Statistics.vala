/* Statistics.vala
 *
 * Copyright 2022 Diego Iván <diegoivan.mae@gmail.com>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Flowtime.Models;

[SingleInstance]
public class Flowtime.Services.Statistics : GLib.Object {
    private Xml.Doc* doc = new Xml.Doc ("1.0");
    private Xml.Node* root_element;

    private string path {
        owned get {
            return Path.build_filename (Environment.get_user_data_dir (), "statistics.xml");
        }
    }

    public Day? today { get; private set; default = null; }

    public List<Day> all_days = new List<Day> ();
    public string productive_day { get; private set; }

    public State total { get; set; default = State (); }
    public State month { get; set; default = State (); }
    public State week { get; set; default = State (); }
    public State today_time { get; set; default = State (); }

    public signal void updated ();

    ~Statistics () {
        delete doc;
    }

    private static Statistics? instance = null;
    public Statistics () {
        if (instance == null) {
            instance = this;
        }
    }

    construct {
        root_element = new Xml.Node (null, "statistics");
        doc->set_root_element (root_element);
        Xml.Node* comment = new Xml.Node.comment ("GENERATED BY FLOWTIME : DO NOT MODIFY");
        root_element->add_child (comment);

        retrieve_statistics.begin ();
    }

    private async void retrieve_statistics () {
        var file = File.new_for_path (path);

        if (!file.query_exists ()) {
            setup_new_statistics_file ();
            save ();
            return;
        }

        doc = Xml.Parser.parse_file (path);
        if (doc == null) {
            warning ("Statistics file was found, but cannot be parsed. Creating a new one");
            setup_new_statistics_file ();

            doc = new Xml.Doc ();
            doc->set_root_element (root_element);
        }

        root_element = doc->get_root_element ();
        retrieve_days ();
        save ();
    }

    private void setup_new_statistics_file () {
        root_element->new_prop ("start", new DateTime.now_utc ().format_iso8601 ());
        today = new Day ();
        root_element->add_child (today.node);
    }

    private void retrieve_days () {
        assert (root_element->name == "statistics");
        DateTime current_date = new DateTime.now_local ();

        int months_saved = settings.get_int ("months-saved");
        Day[] overpassed_days = {};

        const TimeSpan WEEK = TimeSpan.DAY * 7;
        const TimeSpan MONTH = TimeSpan.DAY * 30;

        for (Xml.Node* i = root_element->children; i != null; i = i->next) {
            if (i->type == ELEMENT_NODE) {
                var d = new Day.from_xml (XmlUtils.get_content_node (i, "day"));
                TimeSpan ts = current_date.difference (d.date);

                if (ts > MONTH * months_saved) {
                    overpassed_days += d;
                    continue;
                }

                total.worktime += d.worktime;
                total.breaktime += d.breaktime;
                all_days.append (d);

                if (ts > MONTH) {
                    continue;
                }

                month.worktime += d.worktime;
                month.breaktime += d.breaktime;
                if (ts > WEEK) {
                    continue;
                }

                week.worktime += d.worktime;
                week.breaktime += d.breaktime;

                if (d.date.get_day_of_year () == current_date.get_day_of_year ()) {
                    today = d;
                    today_time.worktime = today.worktime;
                    today_time.breaktime = today.breaktime;
                }
            }
        }

        if (today == null) {
            today = new Day ();
            root_element->add_child (today.node);
            all_days.append (today);
        }

        foreach (var day in overpassed_days) {
            day.unlink ();
        }

        get_most_productive_day.begin ();
    }

    public void add_time_to_mode (TimerMode mode, int time_seconds) {
        switch (mode) {
            case WORK:
                today.worktime += time_seconds;
                week.worktime += time_seconds;
                month.worktime += time_seconds;
                total.worktime += time_seconds;
                break;

            case BREAK:
                today.breaktime += time_seconds;
                week.breaktime += time_seconds;
                month.breaktime += time_seconds;
                total.breaktime += time_seconds;
                break;

            default:
                assert_not_reached ();
        }

        updated ();
    }

    public void foreach_in_period (TimePeriod period, ForeachStat foreach_func) {
        TimeSpan max_timespan = period.get_timespan ();
        var datetime_now = new DateTime.now_utc ();

        foreach (Day day in all_days) {
            TimeSpan ts = day.date.difference (datetime_now);
            if (ts < max_timespan) {
                foreach_func (day);
            }
        }
    }

    private async void get_most_productive_day () {
        var map = new Gee.HashMap<string, int?> ();
        // Now, we will iterate over the all_days list to set the data to the respective day
        for (int i = 0; i < all_days.length (); i++) {
            Day day = all_days.nth_data (i);

            if (!map.has_key (day.day_of_week)) {
                map.set (day.day_of_week, 1);
                continue;
            }

            int count = map.get (day.day_of_week);
            map.unset (day.day_of_week);
            map.set (day.day_of_week, count + 1);
        }

        int highest = 0;
        map.foreach ((entry) => {
            if (entry.value >= highest) {
                productive_day = entry.key;
            }

            return true;
        });
    }

    public void save () {
        doc->save_file (path);
    }
}

public enum Flowtime.Services.TimePeriod {
    TODAY,
    WEEK,
    MONTH,
    ALL;

    internal TimeSpan get_timespan () {
        switch (this) {
            case TODAY:
                return TimeSpan.DAY;
            case WEEK:
                return TimeSpan.DAY * 7;
            case MONTH:
                return TimeSpan.DAY * 30;
            case ALL:
                return TimeSpan.DAY * 30 * 12;
            default:
                assert_not_reached ();
        }
    }
}

public delegate void Flowtime.Services.ForeachStat (Flowtime.Models.Day day);
