library(tidyverse)
library(lubridate)
library(gganimate)


game_goals <-readr::read_csv('https://raw.githubusercontent.com/rfordatascience/tidytuesday/master/data/2020/2020-03-03/game_goals.csv')

# only care for the year of the game
game_goals <- game_goals %>% mutate(year = year(date))

min_year <- min(game_goals$year)
max_year <- max(game_goals$year)

# Find years of each player's  start and retirement
career_years <- game_goals %>%
  group_by(player) %>%
  mutate(year_began = min(year),
         year_retired = max(year)) %>%
  select(player, year_began, year_retired) %>%
  distinct()

# Cumulative goals by year for each player
career_goals <- game_goals %>%
  group_by(player, year) %>%
  summarise(year_goals = sum(goals)) %>%
  ungroup() %>%
  group_by(player) %>%
  arrange(year) %>%
  mutate(career_goals = cumsum(year_goals)) %>%
  ungroup() %>%
  # add full length of years for each player
  complete(nesting(player), year = seq(min_year, max_year, 1L)) %>%
  left_join(career_years, by = c("player")) %>%
  group_by(player) %>%
  mutate(
    career_goals = case_when(
      year < year_began ~ 0,
      year > year_retired ~ max(career_goals),
      TRUE ~ career_goals
    ),
    # For any breaks in the career years, uses previous non-NA value
    career_goals = zoo::na.locf(career_goals, fromLast = FALSE)
  ) %>%
  select(player, year, career_goals) %>%
  arrange(player, year)

# Rank most career goals by player per year
rank_by_year <- career_goals %>%
  # rough interpolation to smooth out ranks in first few years
  group_by(player) %>%
  complete(year = full_seq(year, 1)) %>%
  mutate(career_goals = spline(x = year, y = career_goals, xout = year)$y) %>%
  group_by(year) %>%
  mutate(rank = min_rank(-career_goals) * 1) %>%
  ungroup() %>%
  # interpolate through half years to smooth animation transitions
  group_by(player) %>%
  complete(year = full_seq(year, .5)) %>%
  mutate(career_goals = spline(x = year, y = career_goals, xout = year)$y) %>%
  mutate(rank = approx(x = year, y = rank, xout = year)$y) %>%
  ungroup() %>%
  filter(rank <= 10, year >= 1985) %>%
  arrange(player, year)

anim <- ggplot(rank_by_year,
               aes(rank,
                   group = player,
                   fill = as.factor(player),
                   color = as.factor(player))) +
  geom_tile(aes(y = career_goals / 2,
                height = career_goals,
                width = 0.9),
            alpha = 0.8,
            color = "grey50") +
  geom_text(aes(y = 0, label = paste(player, " ")), vjust = 0.2, hjust = 1) +
  geom_text(aes(y = career_goals,
                label = scales::comma(career_goals)),
            hjust = 0,
            nudge_y = 50) +
  coord_flip(clip = "off", expand = FALSE) +
  scale_y_continuous(labels = scales::comma) +
  scale_x_reverse() +
  guides(color = FALSE, fill = FALSE) +
  labs(title = '{closest_state %>%  as.numeric %>% floor}',
       x = "",
       y = "Career Goals") +
  theme_minimal() +
  theme(
    plot.title = element_text(hjust = 0, size = 22),
    axis.ticks.y = element_blank(),
    axis.text.y = element_blank(),
    plot.margin = margin(1, 1, 1, 4, "cm"),
    panel.grid.major = element_blank(),
    panel.grid.minor = element_blank(),
    axis.line = element_line(color = "black")
  ) +
  transition_states(year, transition_length = 1, state_length = 0) +
  enter_grow() +
  exit_shrink() +
  ease_aes("linear")

animate(
  anim,
  fps = 25,
  nframes = 250,
  duration = 33,
  width = 600,
  height = 400,
  end_pause = 20,
)

anim_save("hockey_goals.gif")
