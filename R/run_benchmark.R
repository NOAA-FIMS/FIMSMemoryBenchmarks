install_fims_debug("main")
# Profile FIMS using jointprof
jointprof_output <- file.path("outputs", "joint_profile.out")
jointprof::start_profiler(jointprof_output)
setup_fims_model()
jointprof::stop_profiler()
jointprof::summary_profiler(jointprof_output)

# Profile FIMS using Rprof
Rprof_output <- file.path("outputs", "Rprof_main.out")
Rprof(NULL)
Rprof(
  filename = Rprof_output,
  memory.profiling = TRUE
)
# code to profile
setup_fims_model()
Rprof(NULL)
summaryRprof(
  filename = Rprof_output, 
  memory = "both",
  lines = c("hide", "show", "both"),
  index = 2, diff = TRUE, exclude = NULL,
  basenames = 1
)


# Profile FIMS using profvis
profvis_output <- profvis::profvis({
  setup_fims_model()
})
saveRDS(profvis_output, file = "outputs/profvis_main.rds")
