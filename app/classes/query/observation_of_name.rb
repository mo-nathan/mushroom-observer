class Query::ObservationOfName < Query::Observation
  include Query::OfName

  def parameter_declarations
    super.merge(
      name: :name,
    ).merge(of_name_parameters)
  end

  def initialize
    give_parameter_defaults
    names = get_target_names
    choose_a_title(names)
    add_name_conditions(names)
    restrict_to_one_project
    restrict_to_one_species_list
    restrict_to_one_user
    super
  end

  def add_join_to_observations_table(table)
    add_join(table)
  end
end