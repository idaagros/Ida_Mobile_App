// lib/localization/app_localizations.dart
//
// Hand-written localization (no `flutter gen-l10n` codegen — see
// app_locale.dart for why). Covers common/shared strings, the Login
// screen, and the Dashboard (including every module tile's label and
// description, looked up by the module's `key` from kModuleDefinitions
// so adding a new module automatically gets an English fallback and
// can get a Marathi translation added in one place).
//
// This is a PILOT covering the first two screens every user sees plus
// the shared vocabulary (Save/Cancel/Delete/etc.) that other screens
// will reuse. Other screens (Electricity, Outward Register, Farm
// Attendance itself, admin screens, ...) aren't translated yet — add
// them the same way: pull the getter from AppLocalizations.of(context)
// instead of a hardcoded string.
//
// To add a new string: add an English value to _localizedValues['en'],
// a Marathi value to _localizedValues['mr'], and a getter below.

import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  Map<String, String> get _strings =>
      _localizedValues[locale.languageCode] ?? _localizedValues['en']!;
  String _t(String key) => _strings[key] ?? _localizedValues['en']![key] ?? key;

  // ── Common / shared ──────────────────────────────────────────
  String get save => _t('save');
  String get cancel => _t('cancel');
  String get delete => _t('delete');
  String get edit => _t('edit');
  String get loading => _t('loading');
  String get search => _t('search');
  String get language => _t('language');
  String get selectLanguage => _t('select_language');
  String get english => _t('english');
  String get marathi => _t('marathi');
  String get logout => _t('logout');

  // ── Login screen ─────────────────────────────────────────────
  String get appTagline => _t('app_tagline');
  String get signIn => _t('sign_in');
  String get enterCredentials => _t('enter_credentials');
  String get usernameLabel => _t('username_label');
  String get passwordLabel => _t('password_label');
  String get enterCredentialsError => _t('enter_credentials_error');
  String get cannotConnectError => _t('cannot_connect_error');
  String get invalidCredentialsError => _t('invalid_credentials_error');

  // ── Dashboard ─────────────────────────────────────────────────
  String welcomeBack(String name) => '${_t('welcome_back')}, $name';
  String get sectionDailyEntries => _t('section_daily_entries');
  String get sectionReportsAnalytics => _t('section_reports_analytics');
  String get sectionPayroll => _t('section_payroll');
  String get sectionFarmOperations => _t('section_farm_operations');
  String get sectionAdministrative => _t('section_administrative');
  String get sectionAdministration => _t('section_administration');

  // Module tile label/description, looked up by kModuleDefinitions' key.
  // Falls back to the English value already in kModuleDefinitions if a
  // module has no translation entry here yet.
  String moduleLabel(String key, String fallback) =>
      _moduleStrings[locale.languageCode]?[key]?['label'] ?? fallback;
  String moduleDescription(String key, String fallback) =>
      _moduleStrings[locale.languageCode]?[key]?['description'] ?? fallback;

  // ── Farm Attendance: entry screen ──────────────────────────────
  String get faTitle => _t('fa_title');
  String get faReportsTooltip => _t('fa_reports_tooltip');
  String get faWorkersAvailableToday => _t('fa_workers_available_today');
  String get faMale => _t('fa_male');
  String get faFemale => _t('fa_female');
  String get faSet => _t('fa_set');
  String faAssignedSummary(int assignedMale, String maleTotal,
          int assignedFemale, String femaleTotal, bool fullyAssigned) =>
      '${_t('fa_assigned')}: $assignedMale/$maleTotal ${_t('fa_male_short')} · $assignedFemale/$femaleTotal ${_t('fa_female_short')}'
      '${fullyAssigned ? ' — ${_t('fa_fully_assigned')}' : ''}';
  String get faAddBatch => _t('fa_add_batch');
  String get faBatchDesc => _t('fa_batch_desc');
  String get faFarm => _t('fa_farm');
  String get faWorkType => _t('fa_work_type');
  String get faSuggestedRate => _t('fa_suggested_rate');
  String get faSelectWorkers => _t('fa_select_workers');
  String get faPerWorkerDayRate => _t('fa_per_worker_day_rate');
  String get faDay => _t('fa_day');
  String get faRateRupee => _t('fa_rate_rupee');
  String get faSaveBatch => _t('fa_save_batch');
  String get faSaving => _t('fa_saving');
  String faEntriesFor(String date) => '${_t('fa_entries_for')} $date';
  String get faTotal => _t('fa_total');
  String get faNoAttendanceToday => _t('fa_no_attendance_today');
  String faDayColon(String fraction) => '${_t('fa_day')}: $fraction';
  String get faSearchWorkers => _t('fa_search_workers');
  String get faNoWorkersMatch => _t('fa_no_workers_match');
  String get faGenderNotSet => _t('fa_gender_not_set');
  String faSelectedCount(int n) => '$n ${_t('fa_selected')}';
  String faTypeToSearch(String label) =>
      '${_t('fa_type_to_search')} ${label.toLowerCase()}';
  String faNoMatches(String label) =>
      locale.languageCode == 'mr' ? '$label जुळत नाही' : 'No $label matches';
  String get faDeleteEntryTitle => _t('fa_delete_entry_title');
  String get faDeleteEntryConfirm => _t('fa_delete_entry_confirm');
  String get faDayFieldHint => _t('fa_day_field_hint');
  String get faRateRupeeLabel => _t('fa_rate_rupee_label');
  String get faErrEnterValidHeadcount => _t('fa_err_headcount');
  String faErrCouldNotReachServer(String e) => '${_t('fa_err_server')}: $e';
  String get faErrServer => _t('fa_err_server');
  String get faErrSelectFarm => _t('fa_err_select_farm');
  String get faErrSelectWorker => _t('fa_err_select_worker');
  String get faWorkersSaved => _t('fa_workers_saved');
  String get faStatusCalendarTooltip => _t('fa_status_calendar_tooltip');
  String get faMarkViaFace => _t('fa_mark_via_face');
  String get faAddWorker => _t('fa_add_worker');
  String get faTodayPresent => _t('fa_today_present');
  String get faExpectedTotalWage => _t('fa_expected_total_wage');
  String get faSubmitting => _t('fa_submitting');
  String get faReviewSubmitAttendance => _t('fa_review_submit_attendance');
  String get faAll => _t('fa_all');
  String get faStatusPendingAttendance => _t('fa_status_pending_attendance');
  String get faStatusApprovedAllocApproved =>
      _t('fa_status_approved_alloc_approved');
  String get faStatusApprovedAllocPending =>
      _t('fa_status_approved_alloc_pending');
  String get faStatusApprovedReady => _t('fa_status_approved_ready');
  String get faStatusReturned => _t('fa_status_returned');
  String get faApprove => _t('fa_approve');
  String get faReject => _t('fa_reject');
  String get faGoToWorkAllocation => _t('fa_go_to_work_allocation');
  String get faAdd => _t('fa_add');
  String get faReviewPresentWorkers => _t('fa_review_present_workers');
  String get faConfirmSubmit => _t('fa_confirm_submit');
  String get faRejectAttendanceTitle => _t('fa_reject_attendance_title');
  String get faRejectAttendanceHint => _t('fa_reject_attendance_hint');
  String get faConfirm => _t('fa_confirm');
  String get faErrSaveHeadcount => _t('fa_err_save_headcount');
  String get faErrSubmitAttendance => _t('fa_err_submit_attendance');
  String get faErrRecordDecision => _t('fa_err_record_decision');
  String get faAlreadyMarkedPresent => _t('fa_already_marked_present');
  String get faMarkedViaFace => _t('fa_marked_via_face');
  String get faAttendanceSubmitted => _t('fa_attendance_submitted');
  String get faWorkerAdded => _t('fa_worker_added');
  String get faStepHeadcount => _t('fa_step_headcount');
  String get faStepAttendancePending => _t('fa_step_attendance_pending');
  String get faStepAttendanceReturned => _t('fa_step_attendance_returned');
  String get faStepAttendanceApproved => _t('fa_step_attendance_approved');
  String get faStepAllocationPending => _t('fa_step_allocation_pending');
  String get faStepAllocationReturned => _t('fa_step_allocation_returned');
  String get faStepComplete => _t('fa_step_complete');
  String get faSelectedLabel => _t('fa_selected_label');
  String get faWaTitle => _t('fa_wa_title');
  String get faWaMustApproveFirst => _t('fa_wa_must_approve_first');
  String get faWaPresentToAllocate => _t('fa_wa_present_to_allocate');
  String get faWaExpectedTotalSuffix => _t('fa_wa_expected_total_suffix');
  String get faWaStatusPending => _t('fa_wa_status_pending');
  String get faWaStatusApproved => _t('fa_wa_status_approved');
  String get faWaTasks => _t('fa_wa_tasks');
  String get faWaAllocatedSuffix => _t('fa_wa_allocated_suffix');
  String get faWaTaskNumber => _t('fa_wa_task_number');
  String get faWaAddMoreWorkersToTask => _t('fa_wa_add_more_workers_to_task');
  String get faWaAssignTaskSelectWorkers =>
      _t('fa_wa_assign_task_select_workers');
  String get faWaAddNewSingleTask => _t('fa_wa_add_new_single_task');
  String get faWaMultiTaskRemaining => _t('fa_wa_multi_task_remaining');
  String get faWaMultiTaskHint => _t('fa_wa_multi_task_hint');
  String get faWaSaving => _t('fa_wa_saving');
  String get faWaSaveAllAllocations => _t('fa_wa_save_all_allocations');
  String get faWaThisMorningSuffix => _t('fa_wa_this_morning_suffix');
  String get faWaSubtotal => _t('fa_wa_subtotal');
  String get faWaAssignTask => _t('fa_wa_assign_task');
  String get faWaEditTasks => _t('fa_wa_edit_tasks');
  String get faWaRemarksHeader => _t('fa_wa_remarks_header');
  String get faWaAllocationsHeader => _t('fa_wa_allocations_header');
  String get faWaTotalPrefix => _t('fa_wa_total_prefix');
  String get faWaRemarkSame => _t('fa_wa_remark_same');
  String get faWaRemarkExcess => _t('fa_wa_remark_excess');
  String get faWaRemarkLess => _t('fa_wa_remark_less');
  String get faWaRemarkUnallocated => _t('fa_wa_remark_unallocated');
  String get faWaRemarkNoMorning => _t('fa_wa_remark_no_morning');
  String get faWaBreakAttendanceNotePrefix =>
      _t('fa_wa_break_attendance_note_prefix');
  String get faWaAllocatedSoFarPrefix => _t('fa_wa_allocated_so_far_prefix');
  String get faWaMatchesExpectedSuffix => _t('fa_wa_matches_expected_suffix');
  String get faWaExpectedSuffix => _t('fa_wa_expected_suffix');
  String get faWaExcessOverSuffix => _t('fa_wa_excess_over_suffix');
  String get faWaLessThanSuffix => _t('fa_wa_less_than_suffix');
  String get faWaRejectTitle => _t('fa_wa_reject_title');
  String get faWaRejectHint => _t('fa_wa_reject_hint');
  String get faWaErrStillNeedTask => _t('fa_wa_err_still_need_task');
  String get faWaErrAddTaskGroup => _t('fa_wa_err_add_task_group');
  String get faWaDidNotWork => _t('fa_wa_did_not_work');
  String get faWaDidNotWorkHint => _t('fa_wa_did_not_work_hint');
  String get faWaAddMissedWorker => _t('fa_wa_add_missed_worker');
  String get faWaAddMissedWorkerHint => _t('fa_wa_add_missed_worker_hint');
  String get faWaWorkerLabel => _t('fa_wa_worker_label');
  String get faWaFarmLabel => _t('fa_wa_farm_label');
  String get faWaWorkTypeOptionalLabel => _t('fa_wa_work_type_optional_label');
  String get faWaReasonLabel => _t('fa_wa_reason_label');
  String get faWaErrSaveAllocation => _t('fa_wa_err_save_allocation');
  String get faWaBreakAttendanceTitlePrefix =>
      _t('fa_wa_break_attendance_title_prefix');
  String get faWaBreakHint => _t('fa_wa_break_hint');
  String get faWaReducedAmountLabel => _t('fa_wa_reduced_amount_label');
  String get faWaReasonHint => _t('fa_wa_reason_hint');
  String get faWaApply => _t('fa_wa_apply');
  String get faWaErrAddFarm => _t('fa_wa_err_add_farm');
  String get faWaErrAmountEveryLine => _t('fa_wa_err_amount_every_line');
  String get faWaAssignTaskTitlePrefix => _t('fa_wa_assign_task_title_prefix');
  String get faWaWorkTypeAddAnotherHeader =>
      _t('fa_wa_work_type_add_another_header');
  String get faWaFarmDropdownLabel => _t('fa_wa_farm_dropdown_label');
  String get faWaWorkTypeDropdownLabel => _t('fa_wa_work_type_dropdown_label');
  String get faWaRateLabel => _t('fa_wa_rate_label');
  String get faWaEnterAmountHint => _t('fa_wa_enter_amount_hint');
  String get faWaBreakShort => _t('fa_wa_break_short');
  String get faWaNotePrefix => _t('fa_wa_note_prefix');
  String get faWaAddAnotherWorkType => _t('fa_wa_add_another_work_type');
  String get faWaRemove => _t('fa_wa_remove');
  String get faWaWorkersForThisTask => _t('fa_wa_workers_for_this_task');
  String get faWaSetThisMorningHint => _t('fa_wa_set_this_morning_hint');
  String get faWaBreakAttendanceLong => _t('fa_wa_break_attendance_long');
  String get faWaErrSelectFarm => _t('fa_wa_err_select_farm');
  String get faWaErrSelectOneWorker => _t('fa_wa_err_select_one_worker');
  String get faWaErrAmountEveryWorker => _t('fa_wa_err_amount_every_worker');
  String get faWaSaveThisTaskGroup => _t('fa_wa_save_this_task_group');
  String get faWaTaskGroupDefaultTitle => _t('fa_wa_task_group_default_title');
  String get faWaTask1FarmWorkersTitle => _t('fa_wa_task1_farm_workers_title');
  String get faCalTitle => _t('fa_cal_title');
  String get faCalErrLoad => _t('fa_cal_err_load');
  String get faCalMon => _t('fa_cal_mon');
  String get faCalTue => _t('fa_cal_tue');
  String get faCalWed => _t('fa_cal_wed');
  String get faCalThu => _t('fa_cal_thu');
  String get faCalFri => _t('fa_cal_fri');
  String get faCalSat => _t('fa_cal_sat');
  String get faCalSun => _t('fa_cal_sun');
  String get faCalLegend => _t('fa_cal_legend');
  String get faCalLegendFullyApproved => _t('fa_cal_legend_fully_approved');
  String get faCalLegendPartiallyApproved =>
      _t('fa_cal_legend_partially_approved');
  String get faCalLegendNotApproved => _t('fa_cal_legend_not_approved');
  String get faCalLegendNoData => _t('fa_cal_legend_no_data');
  String faBatchSavedMsg(int n) => '$n ${_t('fa_workers_saved')}';
  String faBatchSavedWithSkipMsg(int n, int skipped) =>
      '$n ${_t('fa_saved')}, $skipped ${_t('fa_skipped')}';

  // ── Farm Attendance: reports screen ────────────────────────────
  String get faReportsTitle => _t('fa_reports_title');
  String get faWorkerWageReportTitle => _t('fa_worker_wage_report_title');
  String get faWorkerWageReportDesc => _t('fa_worker_wage_report_desc');
  String get faGenderSplitReportTitle => _t('fa_gender_split_report_title');
  String get faGenderSplitReportDesc => _t('fa_gender_split_report_desc');
  String get faFrom => _t('fa_from');
  String get faTo => _t('fa_to');
  String get faGenerateExcelReport => _t('fa_generate_excel_report');
  String get faGenerating => _t('fa_generating');
  String get faReportDownloaded => _t('fa_report_downloaded');
  String faSavedFilename(String f) => '${_t('fa_saved_label')}: $f';
  String get faDynamicReportTitle => _t('fa_dynamic_report_title');
  String get faDynamicReportDesc => _t('fa_dynamic_report_desc');
  String get faSelection1 => _t('fa_selection_1');
  String get faSelection2 => _t('fa_selection_2');
  String get faSelection3 => _t('fa_selection_3');
  String get faGenerate => _t('fa_generate');
  String get faExportToExcel => _t('fa_export_to_excel');
  String get faExporting => _t('fa_exporting');
  String get faNoEntriesRange => _t('fa_no_entries_range');
  String get faTotalDaysCol => _t('fa_total_days_col');
  String get faTotalWageCol => _t('fa_total_wage_col');
  String get faEntriesCol => _t('fa_entries_col');
  String get faGrandTotal => _t('fa_grand_total');
  String get faNone => _t('fa_none');
  String get faWorker => _t('fa_worker');
  String get faGender => _t('fa_gender');

  // ── Farm Attendance: admin masters screen ──────────────────────
  String get faSetupTitle => _t('fa_setup_title');
  String get faFarmsTab => _t('fa_farms_tab');
  String get faWorkTypesTab => _t('fa_work_types_tab');
  String get faWorkersTab => _t('fa_workers_tab');
  String get faAddFarm => _t('fa_add_farm');
  String get faEditFarm => _t('fa_edit_farm');
  String get faFarmNameLabel => _t('fa_farm_name_label');
  String get faLocationOptionalLabel => _t('fa_location_optional_label');
  String get faTotalAreaLabel => _t('fa_total_area_label');
  String get faAddWorkType => _t('fa_add_work_type');
  String get faRenameWorkType => _t('fa_rename_work_type');
  String get faWorkTypeNameHint => _t('fa_work_type_name_hint');
  String get faAddFarmWorker => _t('fa_add_farm_worker');
  String get faEditFarmWorker => _t('fa_edit_farm_worker');
  String get faWorkerNameLabel => _t('fa_worker_name_label');
  String get faDailyWageLabel => _t('fa_daily_wage_label');
  String get faHomeFarmLabel => _t('fa_home_farm_label');
  String get faPhoneOptionalLabel => _t('fa_phone_optional_label');
  String get faNoFarmsYet => _t('fa_no_farms_yet');
  String get faNoWorkTypesYet => _t('fa_no_work_types_yet');
  String get faNoFarmWorkersYet => _t('fa_no_farm_workers_yet');
  String get faMaleFull => _t('fa_male_full');
  String get faFemaleFull => _t('fa_female_full');
  String get faPermanentFull => _t('fa_permanent_full');
  String get faTotalWorkersAvailable => _t('fa_total_workers_available');

  // Farm Tractor
  String get ftSetupTitle => _t('ft_setup_title');
  String get ftTractorsTab => _t('ft_tractors_tab');
  String get ftRatesTab => _t('ft_rates_tab');
  String get ftAddTractor => _t('ft_add_tractor');
  String get ftEditTractor => _t('ft_edit_tractor');
  String get ftTractorNameLabel => _t('ft_tractor_name_label');
  String get ftRegistrationLabel => _t('ft_registration_label');
  String get ftHpLabel => _t('ft_hp_label');
  String get ftNoTractorsYet => _t('ft_no_tractors_yet');
  String get ftNoRatesYet => _t('ft_no_rates_yet');
  String get ftSetRate => _t('ft_set_rate');
  String get ftTractorLabel => _t('ft_tractor_label');
  String get ftWorkTypeLabel => _t('ft_work_type_label');
  String get ftBillingUnitLabel => _t('ft_billing_unit_label');
  String get ftRateLabel => _t('ft_rate_label');
  String get ftEffectiveFromLabel => _t('ft_effective_from_label');
  String get ftScreenTitle => _t('ft_screen_title');
  String get ftDieselLogTooltip => _t('ft_diesel_log_tooltip');
  String get ftSetupTooltip => _t('ft_setup_tooltip');
  String get ftAssignWork => _t('ft_assign_work');
  String get ftFarmLabel => _t('ft_farm_label');
  String get ftHourStartLabel => _t('ft_hour_start_label');
  String get ftNotesLabel => _t('ft_notes_label');
  String get ftSelectRequired => _t('ft_select_required');
  String get ftWorkAssigned => _t('ft_work_assigned');
  String get ftFailedAssign => _t('ft_failed_assign');
  String get ftInProgress => _t('ft_in_progress');
  String get ftCompleted => _t('ft_completed');
  String get ftNoCompletedWork => _t('ft_no_completed_work');
  String get ftTapToComplete => _t('ft_tap_to_complete');
  String get ftHourMeterEndLabel => _t('ft_hour_meter_end_label');
  String get ftStartedAt => _t('ft_started_at');
  String get ftQuantityLabel => _t('ft_quantity_label');
  String get ftBillingChoiceTitle => _t('ft_billing_choice_title');
  String get ftCompleteButton => _t('ft_complete_button');
  String get ftWorkCompleted => _t('ft_work_completed');
  String get ftFailedComplete => _t('ft_failed_complete');
  String get ftDieselTitle => _t('ft_diesel_title');
  String get ftAddFillup => _t('ft_add_fillup');
  String get ftDateLabel => _t('ft_date_label');
  String get ftLitersLabel => _t('ft_liters_label');
  String get ftCostLabel => _t('ft_cost_label');
  String get ftHourMeterReadingLabel => _t('ft_hour_meter_reading_label');
  String get ftHourMeterHelper => _t('ft_hour_meter_helper');
  String get ftAverageFuelUse => _t('ft_average_fuel_use');
  String get ftFillupHistory => _t('ft_fillup_history');
  String get ftNoDieselLogs => _t('ft_no_diesel_logs');
  String get ftNoTractorsSetupFirst => _t('ft_no_tractors_setup_first');

  // Crop Planning (agri)
  String get agriCropMastersTitle => _t('agri_crop_masters_title');
  String get agriCropsTab => _t('agri_crops_tab');
  String get agriVarietiesTab => _t('agri_varieties_tab');
  String get agriAgronomySetupTitle => _t('agri_agronomy_setup_title');
  String get agriOrchardBlocksTab => _t('agri_orchard_blocks_tab');
  String get agriStageTemplatesTab => _t('agri_stage_templates_tab');
  String get agriSprayTemplatesTab => _t('agri_spray_templates_tab');
  String get agriAddCrop => _t('agri_add_crop');
  String get agriEditCrop => _t('agri_edit_crop');
  String get agriCropNameLabel => _t('agri_crop_name_label');
  String get agriCategoryLabel => _t('agri_category_label');
  String get agriCropTypeLabel => _t('agri_crop_type_label');
  String get agriSeasonal => _t('agri_seasonal');
  String get agriPerennial => _t('agri_perennial');
  String get agriAddVariety => _t('agri_add_variety');
  String get agriEditVariety => _t('agri_edit_variety');
  String get agriVarietyNameLabel => _t('agri_variety_name_label');
  String get agriSourceNotesLabel => _t('agri_source_notes_label');
  String get agriMaturityDaysLabel => _t('agri_maturity_days_label');
  String get agriStdYieldLabel => _t('agri_std_yield_label');
  String get agriYieldUnitLabel => _t('agri_yield_unit_label');
  String get agriAddOrchardBlock => _t('agri_add_orchard_block');
  String get agriEditOrchardBlock => _t('agri_edit_orchard_block');
  String get agriFarmLabel => _t('agri_farm_label');
  String get agriVarietyLabel => _t('agri_variety_label');
  String get agriPlantingDateLabel => _t('agri_planting_date_label');
  String get agriNoOfTreesLabel => _t('agri_no_of_trees_label');
  String get agriAreaAcreLabel => _t('agri_area_acre_label');
  String get agriStatusLabel => _t('agri_status_label');
  String get agriAddStageTemplate => _t('agri_add_stage_template');
  String get agriEditStageTemplate => _t('agri_edit_stage_template');
  String get agriStageNameLabel => _t('agri_stage_name_label');
  String get agriTriggerTypeLabel => _t('agri_trigger_type_label');
  String get agriTriggerDaysStartLabel => _t('agri_trigger_days_start_label');
  String get agriTriggerDaysEndLabel => _t('agri_trigger_days_end_label');
  String get agriTreeAgeBracketLabel => _t('agri_tree_age_bracket_label');
  String get agriNotesLabel => _t('agri_notes_label');
  String get agriAddSprayTemplate => _t('agri_add_spray_template');
  String get agriEditSprayTemplate => _t('agri_edit_spray_template');
  String get agriTriggerDaysLabel => _t('agri_trigger_days_label');
  String get agriActivityTypeLabel => _t('agri_activity_type_label');
  String get agriProductSuggestionLabel => _t('agri_product_suggestion_label');
  String get agriDosePerAcreLabel => _t('agri_dose_per_acre_label');
  String get agriDosePerTreeLabel => _t('agri_dose_per_tree_label');
  String get agriDoseUnitLabel => _t('agri_dose_unit_label');
  String get agriSequenceOrderLabel => _t('agri_sequence_order_label');
  String get agriNoCropsYet => _t('agri_no_crops_yet');
  String get agriNoVarietiesYet => _t('agri_no_varieties_yet');
  String get agriNoOrchardBlocksYet => _t('agri_no_orchard_blocks_yet');
  String get agriNoStageTemplatesYet => _t('agri_no_stage_templates_yet');
  String get agriNoSprayTemplatesYet => _t('agri_no_spray_templates_yet');
  String get agriSaved => _t('agri_saved');
  String get agriFailedSave => _t('agri_failed_save');
  String get agriCyclesTitle => _t('agri_cycles_title');
  String get agriAddSowingPlan => _t('agri_add_sowing_plan');
  String get agriAddOrchardCycle => _t('agri_add_orchard_cycle');
  String get agriSeasonLabel => _t('agri_season_label');
  String get agriSowingDateLabel => _t('agri_sowing_date_label');
  String get agriAreaSownLabel => _t('agri_area_sown_label');
  String get agriSpacingSectionHeader => _t('agri_spacing_section_header');
  String get agriRowSpacingLabel => _t('agri_row_spacing_label');
  String get agriPlantSpacingLabel => _t('agri_plant_spacing_label');
  String get agriUnitFt => _t('agri_unit_ft');
  String get agriUnitIn => _t('agri_unit_in');
  String get agriUnitCm => _t('agri_unit_cm');
  String get agriRowArrangementLabel => _t('agri_row_arrangement_label');
  String get agriArrangementUniform => _t('agri_arrangement_uniform');
  String get agriArrangementPaired => _t('agri_arrangement_paired');
  String get agriIntraPairLabel => _t('agri_intra_pair_label');
  String get agriInterPairLabel => _t('agri_inter_pair_label');
  String get agriAddIntercropButton => _t('agri_add_intercrop_button');
  String get agriAddIntercropTitle => _t('agri_add_intercrop_title');
  String get agriIntercropHint => _t('agri_intercrop_hint');
  String get agriIntercropVarietyLabel => _t('agri_intercrop_variety_label');
  String get agriMainRowsPerCycleLabel => _t('agri_main_rows_per_cycle_label');
  String get agriIntercropRowsPerCycleLabel =>
      _t('agri_intercrop_rows_per_cycle_label');
  String get agriSharedAreaLabel => _t('agri_shared_area_label');
  String get agriIntercropAddedMsg => _t('agri_intercrop_added_msg');
  String get agriIntercropGroupHeader => _t('agri_intercrop_group_header');
  String get agriCalculatedAreaNote => _t('agri_calculated_area_note');
  String get agriOrchardBlockLabel => _t('agri_orchard_block_label');
  String get agriCycleYearLabel => _t('agri_cycle_year_label');
  String get agriBaharNameLabel => _t('agri_bahar_name_label');
  String get agriFloweringStartLabel => _t('agri_flowering_start_label');
  String get agriNoCyclesYet => _t('agri_no_cycles_yet');
  String get agriScheduleGenerated => _t('agri_schedule_generated');
  String get agriCalendarTitle => _t('agri_calendar_title');
  String get agriOverdueSection => _t('agri_overdue_section');
  String get agriPendingSection => _t('agri_pending_section');
  String get agriNotScheduledSection => _t('agri_not_scheduled_section');
  String get agriDoneSection => _t('agri_done_section');
  String get agriSkippedSection => _t('agri_skipped_section');
  String get agriWaitingOn => _t('agri_waiting_on');
  String get agriMarkComplete => _t('agri_mark_complete');
  String get agriSkipAction => _t('agri_skip_action');
  String get agriOperationDateLabel => _t('agri_operation_date_label');
  String get agriCostLabel => _t('agri_cost_label');
  String get agriWorkerLabel => _t('agri_worker_label');
  String get agriSkipRemarksLabel => _t('agri_skip_remarks_label');
  String get agriDelayDays => _t('agri_delay_days');
  String get agriEarlyDays => _t('agri_early_days');
  String get agriOnTime => _t('agri_on_time');
  String get agriLogLabor => _t('agri_log_labor');
  String get agriLogHarvest => _t('agri_log_harvest');
  String get agriPaymentModeLabel => _t('agri_payment_mode_label');
  String get agriDaily => _t('agri_daily');
  String get agriPieceRate => _t('agri_piece_rate');
  String get agriDaysWorkedLabel => _t('agri_days_worked_label');
  String get agriDailyWageLabel => _t('agri_daily_wage_label');
  String get agriQtyHarvestedLabel => _t('agri_qty_harvested_label');
  String get agriRatePerKgLabel => _t('agri_rate_per_kg_label');
  String get agriHarvestDateLabel => _t('agri_harvest_date_label');
  String get agriTotalYieldLabel => _t('agri_total_yield_label');
  String get agriUnitLabel => _t('agri_unit_label');
  String get agriQualityGradeLabel => _t('agri_quality_grade_label');
  String get agriComputedCostPreview => _t('agri_computed_cost_preview');
  String get agriReportsTitle => _t('agri_reports_title');
  String get agriPlanningTab => _t('agri_planning_tab');
  String get agriCostYieldTab => _t('agri_cost_yield_tab');
  String get agriFromDateLabel => _t('agri_from_date_label');
  String get agriToDateLabel => _t('agri_to_date_label');
  String get agriAllFarms => _t('agri_all_farms');
  String get agriAllVarieties => _t('agri_all_varieties');
  String get agriOverdueOnly => _t('agri_overdue_only');
  String get agriPendingOnly => _t('agri_pending_only');
  String get agriTotalItems => _t('agri_total_items');
  String get agriByFarm => _t('agri_by_farm');
  String get agriNoPendingItems => _t('agri_no_pending_items');
  String get agriGroupByLabel => _t('agri_group_by_label');
  String get agriGenerateReport => _t('agri_generate_report');
  String get agriExportExcel => _t('agri_export_excel');
  String get agriInputCostCol => _t('agri_input_cost_col');
  String get agriLaborCostCol => _t('agri_labor_cost_col');
  String get agriTotalCostCol => _t('agri_total_cost_col');
  String get agriYieldCol => _t('agri_yield_col');
  String get agriCostPerKgCol => _t('agri_cost_per_kg_col');
  String get agriGrandTotal => _t('agri_grand_total');
  String get agriNoReportYet => _t('agri_no_report_yet');
  String get agriSelectDateRange => _t('agri_select_date_range');
  String get sectorPickerTitle => _t('sector_picker_title');
  String get sectorPickerSubtitle => _t('sector_picker_subtitle');
  String get sectorFactoryLabel => _t('sector_factory_label');
  String get sectorFactoryDesc => _t('sector_factory_desc');
  String get sectorAgricultureLabel => _t('sector_agriculture_label');
  String get sectorAgricultureDesc => _t('sector_agriculture_desc');
  String get sectorSwitchTitle => _t('sector_switch_title');

  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'edit': 'Edit',
      'loading': 'Loading…',
      'search': 'Search',
      'language': 'Language',
      'select_language': 'Select language',
      'english': 'English',
      'marathi': 'मराठी (Marathi)',
      'logout': 'Logout',
      'app_tagline': 'Daily Reporting & Register',
      'sign_in': 'Sign in',
      'enter_credentials': 'Enter your credentials to continue',
      'username_label': 'Username',
      'password_label': 'Password',
      'enter_credentials_error': 'Please enter your username and password.',
      'cannot_connect_error':
          'Cannot connect to server. Check your connection.',
      'invalid_credentials_error': 'Invalid credentials. Please try again.',
      'welcome_back': 'Welcome back',
      'section_daily_entries': 'Daily Entries',
      'section_reports_analytics': 'Reports & Analytics',
      'section_payroll': 'Payroll',
      'section_farm_operations': 'Farm Operations',
      'section_administrative': 'Administrative',
      'section_administration': 'Administration',

      // Farm Attendance — entry screen
      'fa_title': 'Farm Attendance',
      'fa_reports_tooltip': 'Reports',
      'fa_workers_available_today': 'WORKERS AVAILABLE TODAY',
      'fa_male': 'Male',
      'fa_female': 'Female',
      'fa_male_full': 'Male',
      'fa_female_full': 'Female',
      'fa_permanent_full': 'Permanent',
      'fa_total_workers_available': 'Total workers available',
      'fa_male_short': 'male',
      'fa_female_short': 'female',
      'fa_set': 'Set',
      'fa_assigned': 'Assigned',
      'fa_fully_assigned': 'fully assigned',
      'fa_add_batch': 'ADD A BATCH',
      'fa_batch_desc':
          'One farm + one work type + a suggested rate, then pick everyone doing that task.',
      'fa_farm': 'Farm',
      'fa_work_type': 'Work Type',
      'fa_suggested_rate': 'Suggested rate (₹) for this batch',
      'fa_select_workers': 'SELECT WORKERS',
      'fa_per_worker_day_rate': 'PER-WORKER DAY & RATE',
      'fa_day': 'Day',
      'fa_rate_rupee': 'Rate ₹',
      'fa_save_batch': 'Save Batch',
      'fa_saving': 'Saving…',
      'fa_entries_for': 'Entries for',
      'fa_total': 'Total',
      'fa_no_attendance_today': 'No attendance recorded for this date yet',
      'fa_search_workers': 'Search workers…',
      'fa_no_workers_match': 'No workers match',
      'fa_gender_not_set': 'Gender not set',
      'fa_selected': 'selected',
      'fa_type_to_search': 'Type to search',
      'fa_delete_entry_title': 'Delete entry?',
      'fa_delete_entry_confirm':
          'This attendance entry will be permanently removed.',
      'fa_day_field_hint': 'Day (1, 0.5, 1.5, ...)',
      'fa_rate_rupee_label': 'Rate (₹)',
      'fa_err_headcount':
          'Enter a valid male and female worker count (0 or more)',
      'fa_err_server': 'Could not reach server',
      'fa_err_select_farm': 'Select a farm for this batch',
      'fa_err_select_worker': 'Select at least one worker',
      'fa_workers_saved': 'worker(s) saved',
      'fa_saved': 'saved',
      'fa_skipped': 'skipped (already recorded for this date/farm/work type)',
      'fa_status_calendar_tooltip': 'Status Calendar',
      'fa_mark_via_face': 'Mark via Face',
      'fa_add_worker': 'Add Worker',
      'fa_today_present': 'TODAY PRESENT',
      'fa_expected_total_wage': 'Expected Total Wage',
      'fa_submitting': 'Submitting…',
      'fa_review_submit_attendance': 'Review & Submit Attendance',
      'fa_all': 'All',
      'fa_status_pending_attendance':
          'Attendance submitted — awaiting admin approval',
      'fa_status_approved_alloc_approved':
          'Attendance approved · Work allocation approved',
      'fa_status_approved_alloc_pending':
          'Attendance approved · Work allocation awaiting approval',
      'fa_status_approved_ready':
          'Attendance approved — ready for work allocation',
      'fa_status_returned': 'Returned for correction',
      'fa_approve': 'Approve',
      'fa_reject': 'Reject',
      'fa_go_to_work_allocation': 'Go to Work Allocation',
      'fa_add': 'Add',
      'fa_review_present_workers': 'Review Present Workers',
      'fa_confirm_submit': 'Confirm & Submit',
      'fa_reject_attendance_title': 'Reject attendance',
      'fa_reject_attendance_hint':
          'Why is this being sent back for correction?',
      'fa_confirm': 'Confirm',
      'fa_err_save_headcount': 'Failed to save headcount',
      'fa_err_submit_attendance': 'Failed to submit attendance',
      'fa_err_record_decision': 'Failed to record decision',
      'fa_already_marked_present': 'is already marked present',
      'fa_marked_via_face': 'marked present via face recognition',
      'fa_attendance_submitted': 'Attendance submitted for approval',
      'fa_worker_added': 'Worker added',
      'fa_step_headcount': 'Step 1 of 5 — Set today\'s headcount',
      'fa_step_attendance_pending':
          'Step 2 of 5 — Attendance awaiting approval',
      'fa_step_attendance_returned':
          'Step 2 of 5 — Attendance returned, needs correction',
      'fa_step_attendance_approved':
          'Step 3 of 5 — Attendance approved, ready to allocate work',
      'fa_step_allocation_pending':
          'Step 4 of 5 — Work allocation awaiting approval',
      'fa_step_allocation_returned':
          'Step 4 of 5 — Work allocation returned, needs correction',
      'fa_step_complete': 'Step 5 of 5 — Complete',
      'fa_selected_label': 'Selected',
      'fa_wa_title': 'Work Allocation',
      'fa_wa_must_approve_first':
          "Today's attendance must be approved before work can be allocated.",
      'fa_wa_present_to_allocate': 'present worker(s) to allocate.',
      'fa_wa_expected_total_suffix': 'Expected total',
      'fa_wa_status_pending':
          'Work allocation submitted — awaiting admin approval',
      'fa_wa_status_approved': 'Work allocation approved — final',
      'fa_wa_tasks': 'TASKS',
      'fa_wa_allocated_suffix': 'allocated',
      'fa_wa_task_number': 'TASK',
      'fa_wa_add_more_workers_to_task': 'Add More Workers to Task',
      'fa_wa_assign_task_select_workers': 'Assign Task — Select Workers',
      'fa_wa_add_new_single_task': 'Add New Single Task',
      'fa_wa_multi_task_remaining': 'MULTI TASK — REMAINING WORKERS',
      'fa_wa_multi_task_hint':
          'Each worker can be split across more than one Farm + Work Type — tap + to add another.',
      'fa_wa_saving': 'Saving…',
      'fa_wa_save_all_allocations': 'Save All Allocations',
      'fa_wa_this_morning_suffix': 'this morning',
      'fa_wa_subtotal': 'Subtotal',
      'fa_wa_assign_task': 'Assign Task',
      'fa_wa_edit_tasks': 'Edit Tasks',
      'fa_wa_remarks_header': 'REMARKS — MORNING AMOUNT VS ALLOCATED',
      'fa_wa_allocations_header': 'ALLOCATIONS',
      'fa_wa_total_prefix': 'Total',
      'fa_wa_remark_same': 'Same as morning',
      'fa_wa_remark_excess': 'Excess by',
      'fa_wa_remark_less': 'Less by',
      'fa_wa_remark_unallocated': 'Not allocated',
      'fa_wa_remark_no_morning': 'No morning amount on file',
      'fa_wa_break_attendance_note_prefix': 'Break Attendance',
      'fa_wa_allocated_so_far_prefix': 'Allocated so far',
      'fa_wa_matches_expected_suffix': 'matches the',
      'fa_wa_expected_suffix': 'expected',
      'fa_wa_excess_over_suffix': 'excess over the',
      'fa_wa_less_than_suffix': 'less than the',
      'fa_wa_reject_title': 'Reject work allocation',
      'fa_wa_reject_hint': 'Why is this being sent back for correction?',
      'fa_wa_err_still_need_task': 'present worker(s) still need a task:',
      'fa_wa_err_add_task_group': 'Add at least one task group',
      'fa_wa_did_not_work': 'Did not work',
      'fa_wa_did_not_work_hint':
          'They were marked present this morning but did not actually work — removed from today\'s present count entirely, and no wage will be paid.',
      'fa_wa_add_missed_worker': 'Add Missed Worker',
      'fa_wa_add_missed_worker_hint':
          'For a worker who actually worked today but was left out of the original headcount. Adds them to today\'s present count and pays them directly — final immediately, no further approval needed.',
      'fa_wa_worker_label': 'Worker',
      'fa_wa_farm_label': 'Farm',
      'fa_wa_work_type_optional_label': 'Work type (optional)',
      'fa_wa_reason_label': 'Reason',
      'fa_wa_err_save_allocation': 'Failed to save allocation',
      'fa_wa_break_attendance_title_prefix': 'Break Attendance',
      'fa_wa_break_hint':
          'Left before day end? Reduce the amount and note the reason.',
      'fa_wa_reduced_amount_label': 'Reduced amount (₹)',
      'fa_wa_reason_hint': 'Reason (e.g. Left at 1pm — unwell)',
      'fa_wa_apply': 'Apply',
      'fa_wa_err_add_farm': 'Add at least one Farm for this worker',
      'fa_wa_err_amount_every_line': 'Enter an amount for every task line',
      'fa_wa_assign_task_title_prefix': 'Assign Task',
      'fa_wa_work_type_add_another_header': 'WORK TYPE — TAP + TO ADD ANOTHER',
      'fa_wa_farm_dropdown_label': 'Farm',
      'fa_wa_work_type_dropdown_label': 'Work Type',
      'fa_wa_rate_label': 'Rate ₹',
      'fa_wa_enter_amount_hint': 'Enter amount',
      'fa_wa_break_short': 'Break',
      'fa_wa_note_prefix': 'Note',
      'fa_wa_add_another_work_type': 'Add Another Work Type',
      'fa_wa_remove': 'Remove',
      'fa_wa_workers_for_this_task': 'WORKERS FOR THIS TASK',
      'fa_wa_set_this_morning_hint': 'Set this morning — admin can change',
      'fa_wa_break_attendance_long': 'Break Attendance',
      'fa_wa_err_select_farm': 'Select a farm',
      'fa_wa_err_select_one_worker': 'Select at least one worker',
      'fa_wa_err_amount_every_worker':
          'Enter an amount for every selected worker',
      'fa_wa_save_this_task_group': 'Save This Task Group',
      'fa_wa_task_group_default_title': 'Task Group',
      'fa_wa_task1_farm_workers_title': 'Task 1 — Farm & Workers',
      'fa_cal_title': 'Attendance Status Calendar',
      'fa_cal_err_load': 'Failed to load calendar',
      'fa_cal_mon': 'Mon',
      'fa_cal_tue': 'Tue',
      'fa_cal_wed': 'Wed',
      'fa_cal_thu': 'Thu',
      'fa_cal_fri': 'Fri',
      'fa_cal_sat': 'Sat',
      'fa_cal_sun': 'Sun',
      'fa_cal_legend': 'LEGEND',
      'fa_cal_legend_fully_approved':
          'Fully approved — attendance & work allocation both approved',
      'fa_cal_legend_partially_approved':
          'Partially approved — attendance approved, allocation not yet',
      'fa_cal_legend_not_approved':
          'Not approved — attendance still pending or returned',
      'fa_cal_legend_no_data': 'No attendance marked for this date',

      // Farm Attendance — reports screen
      'fa_reports_title': 'Attendance Reports',
      'fa_worker_wage_report_title': 'Worker Wage Report',
      'fa_worker_wage_report_desc':
          'One row per worker, each date as its own Days / Amount / Farm / Work Type block, with a running total per worker.',
      'fa_gender_split_report_title': 'Worker Wage Report — Male/Female Split',
      'fa_gender_split_report_desc':
          'One row per worker, one column per date, a total per worker — shown in two separate tables, Male and Female, each with its own subtotal.',
      'fa_from': 'From',
      'fa_to': 'To',
      'fa_generate_excel_report': 'Generate Excel Report',
      'fa_generating': 'Generating…',
      'fa_report_downloaded': 'Report downloaded',
      'fa_saved_label': 'Saved',
      'fa_dynamic_report_title': 'Dynamic Report (Slice & Dice)',
      'fa_dynamic_report_desc':
          'Pick grouping levels in order — leave any as "None" to skip it. Totals are days worked and wage.',
      'fa_selection_1': '1st selection',
      'fa_selection_2': '2nd selection',
      'fa_selection_3': '3rd selection',
      'fa_generate': 'Generate',
      'fa_export_to_excel': 'Export to Excel',
      'fa_exporting': 'Exporting…',
      'fa_no_entries_range': 'No attendance entries found for this date range.',
      'fa_total_days_col': 'Total Days',
      'fa_total_wage_col': 'Total Wage',
      'fa_entries_col': 'Entries',
      'fa_grand_total': 'Grand total',
      'fa_none': 'None',
      'fa_worker': 'Worker',
      'fa_gender': 'Gender',

      // Farm Attendance — admin masters screen
      'fa_setup_title': 'Farm Attendance Setup',
      'fa_farms_tab': 'Farms',
      'fa_work_types_tab': 'Work Types',
      'fa_workers_tab': 'Workers',
      'fa_add_farm': 'Add Farm',
      'fa_edit_farm': 'Edit Farm',
      'fa_farm_name_label': 'Farm name',
      'fa_location_optional_label': 'Location (optional)',
      'fa_total_area_label': 'Total farm area (acres)',
      'fa_add_work_type': 'Add Work Type',
      'fa_rename_work_type': 'Rename Work Type',
      'fa_work_type_name_hint': 'Work type name',
      'fa_add_farm_worker': 'Add Farm Worker',
      'fa_edit_farm_worker': 'Edit Farm Worker',
      'fa_worker_name_label': 'Worker name',
      'fa_daily_wage_label': 'Daily wage (₹)',
      'fa_home_farm_label': 'Home farm',
      'fa_phone_optional_label': 'Phone (optional)',
      'fa_no_farms_yet': 'No farms yet — tap + to add one',
      'fa_no_work_types_yet': 'No work types yet — tap + to add one',
      'fa_no_farm_workers_yet': 'No farm workers yet — tap + to add one',
      // Farm Tractor
      'ft_setup_title': 'Farm Tractor Setup',
      'ft_tractors_tab': 'Tractors',
      'ft_rates_tab': 'Rates',
      'ft_add_tractor': 'Add Tractor',
      'ft_edit_tractor': 'Edit Tractor',
      'ft_tractor_name_label': 'Tractor name',
      'ft_registration_label': 'Registration number (optional)',
      'ft_hp_label': 'HP (optional)',
      'ft_no_tractors_yet': 'No tractors yet — tap + to add one',
      'ft_no_rates_yet': 'No rates set yet — tap + to add one',
      'ft_set_rate': 'Set Rate',
      'ft_tractor_label': 'Tractor',
      'ft_work_type_label': 'Work Type',
      'ft_billing_unit_label': 'Billed per',
      'ft_rate_label': 'Rate (₹)',
      'ft_effective_from_label': 'Effective from',
      'ft_screen_title': 'Farm Tractor',
      'ft_diesel_log_tooltip': 'Diesel Log',
      'ft_setup_tooltip': 'Setup',
      'ft_assign_work': 'Assign Work',
      'ft_farm_label': 'Farm',
      'ft_hour_start_label': 'Hour meter start (optional)',
      'ft_notes_label': 'Notes (optional)',
      'ft_select_required': 'Select tractor, farm and work type',
      'ft_work_assigned': 'Work assigned',
      'ft_failed_assign': 'Failed to assign work',
      'ft_in_progress': 'IN PROGRESS',
      'ft_completed': 'COMPLETED',
      'ft_no_completed_work': 'No completed work for this date',
      'ft_tap_to_complete': 'Tap to complete',
      'ft_hour_meter_end_label': 'Hour meter end',
      'ft_started_at': 'Started at',
      'ft_quantity_label': 'Quantity',
      'ft_billing_choice_title': 'How is this job billed?',
      'ft_complete_button': 'Complete',
      'ft_work_completed': 'Work completed',
      'ft_failed_complete': 'Failed to complete',
      'ft_diesel_title': 'Diesel Log',
      'ft_add_fillup': 'Add Diesel Fill-up',
      'ft_date_label': 'Date',
      'ft_liters_label': 'Liters filled',
      'ft_cost_label': 'Cost (₹, optional)',
      'ft_hour_meter_reading_label': 'Hour meter reading (optional)',
      'ft_hour_meter_helper': 'Needed for the fuel-average calculation',
      'ft_average_fuel_use': 'AVERAGE FUEL USE',
      'ft_fillup_history': 'FILL-UP HISTORY',
      'ft_no_diesel_logs': 'No diesel logs yet — tap + to add one',
      'ft_no_tractors_setup_first': 'No tractors yet — add one in Setup first',
      // Crop Planning (agri)
      'agri_crop_masters_title': 'Crop Masters',
      'agri_crops_tab': 'Crops',
      'agri_varieties_tab': 'Varieties',
      'agri_agronomy_setup_title': 'Agronomy Setup',
      'agri_orchard_blocks_tab': 'Orchard Blocks',
      'agri_stage_templates_tab': 'Stage Templates',
      'agri_spray_templates_tab': 'Spray Templates',
      'agri_add_crop': 'Add Crop',
      'agri_edit_crop': 'Edit Crop',
      'agri_crop_name_label': 'Crop name',
      'agri_category_label': 'Category (optional)',
      'agri_crop_type_label': 'Crop type',
      'agri_seasonal': 'Seasonal',
      'agri_perennial': 'Perennial',
      'agri_add_variety': 'Add Variety',
      'agri_edit_variety': 'Edit Variety',
      'agri_variety_name_label': 'Variety name',
      'agri_source_notes_label': 'Source notes (optional)',
      'agri_maturity_days_label': 'Maturity days (optional)',
      'agri_std_yield_label': 'Standard yield per plant (optional)',
      'agri_yield_unit_label': 'Yield unit (optional)',
      'agri_add_orchard_block': 'Add Orchard Block',
      'agri_edit_orchard_block': 'Edit Orchard Block',
      'agri_farm_label': 'Farm',
      'agri_variety_label': 'Variety',
      'agri_planting_date_label': 'Planting date',
      'agri_no_of_trees_label': 'No. of trees (optional)',
      'agri_area_acre_label': 'Area (acre, optional)',
      'agri_status_label': 'Status',
      'agri_add_stage_template': 'Add Stage Template',
      'agri_edit_stage_template': 'Edit Stage Template',
      'agri_stage_name_label': 'Stage name',
      'agri_trigger_type_label': 'Trigger type',
      'agri_trigger_days_start_label': 'Trigger days — start',
      'agri_trigger_days_end_label': 'Trigger days — end',
      'agri_tree_age_bracket_label': 'Tree age bracket (optional)',
      'agri_notes_label': 'Notes (optional)',
      'agri_add_spray_template': 'Add Spray Template',
      'agri_edit_spray_template': 'Edit Spray Template',
      'agri_trigger_days_label': 'Trigger days',
      'agri_activity_type_label': 'Activity type',
      'agri_product_suggestion_label': 'Product suggestion (optional)',
      'agri_dose_per_acre_label': 'Dose per acre',
      'agri_dose_per_tree_label': 'Dose per tree',
      'agri_dose_unit_label': 'Dose unit (optional)',
      'agri_sequence_order_label': 'Sequence order (optional)',
      'agri_no_crops_yet': 'No crops yet — tap + to add one',
      'agri_no_varieties_yet': 'No varieties yet — tap + to add one',
      'agri_no_orchard_blocks_yet': 'No orchard blocks yet — tap + to add one',
      'agri_no_stage_templates_yet':
          'No stage templates yet — tap + to add one',
      'agri_no_spray_templates_yet':
          'No spray templates yet — tap + to add one',
      'agri_saved': 'Saved',
      'agri_failed_save': 'Failed to save',
      'agri_cycles_title': 'Crop Cycles',
      'agri_add_sowing_plan': 'New Sowing Plan',
      'agri_add_orchard_cycle': 'New Orchard Cycle',
      'agri_season_label': 'Season',
      'agri_sowing_date_label': 'Sowing date',
      'agri_area_sown_label': 'Area sown (acre, optional)',
      'agri_spacing_section_header': 'Row & Plant Spacing (optional)',
      'agri_row_spacing_label': 'Row to row spacing',
      'agri_plant_spacing_label': 'Plant to plant spacing',
      'agri_unit_ft': 'Feet',
      'agri_unit_in': 'Inch',
      'agri_unit_cm': 'Centimeter',
      'agri_row_arrangement_label': 'Row arrangement',
      'agri_arrangement_uniform': 'Uniform',
      'agri_arrangement_paired': 'Paired rows',
      'agri_intra_pair_label': 'Distance within a pair',
      'agri_inter_pair_label': 'Gap between pairs',
      'agri_add_intercrop_button': 'Add Intercrop',
      'agri_add_intercrop_title': 'Add Intercrop',
      'agri_intercrop_hint':
          'For fields where a second crop is sown in a repeating row pattern alongside the main crop (e.g. every 6 rows of Soybean, 2 rows of Tur).',
      'agri_intercrop_variety_label': 'Intercrop variety',
      'agri_main_rows_per_cycle_label': 'Main crop rows per cycle',
      'agri_intercrop_rows_per_cycle_label': 'Intercrop rows per cycle',
      'agri_shared_area_label': 'Total physical area of this field (acres)',
      'agri_intercrop_added_msg':
          'Intercrop added — area recalculated for both crops',
      'agri_intercrop_group_header': 'INTERCROPPED WITH',
      'agri_calculated_area_note':
          'Area calculated automatically from row pattern',
      'agri_orchard_block_label': 'Orchard Block',
      'agri_cycle_year_label': 'Cycle year',
      'agri_bahar_name_label': 'Bahar name (optional)',
      'agri_flowering_start_label': 'Flowering start date (optional)',
      'agri_no_cycles_yet': 'No crop cycles yet — tap + to start one',
      'agri_schedule_generated': 'Cycle created — schedule generated',
      'agri_calendar_title': 'Crop Calendar',
      'agri_overdue_section': 'OVERDUE',
      'agri_pending_section': 'UPCOMING',
      'agri_not_scheduled_section': 'NOT YET SCHEDULED',
      'agri_done_section': 'DONE',
      'agri_skipped_section': 'SKIPPED',
      'agri_waiting_on': 'Waiting on',
      'agri_mark_complete': 'Mark Complete',
      'agri_skip_action': 'Skip — Not Done / Not Needed',
      'agri_operation_date_label': 'Date it was actually done',
      'agri_cost_label': 'Cost (₹)',
      'agri_worker_label': 'Worker (optional)',
      'agri_skip_remarks_label': 'Why is this being skipped?',
      'agri_delay_days': 'days late',
      'agri_early_days': 'days early',
      'agri_on_time': 'On time',
      'agri_log_labor': 'Log Labor',
      'agri_log_harvest': 'Log Harvest',
      'agri_payment_mode_label': 'Payment mode',
      'agri_daily': 'Daily wage',
      'agri_piece_rate': 'Piece rate',
      'agri_days_worked_label': 'Days worked',
      'agri_daily_wage_label': 'Daily wage (₹)',
      'agri_qty_harvested_label': 'Quantity harvested (kg)',
      'agri_rate_per_kg_label': 'Rate per kg (₹)',
      'agri_harvest_date_label': 'Harvest date',
      'agri_total_yield_label': 'Total yield quantity',
      'agri_unit_label': 'Unit',
      'agri_quality_grade_label': 'Quality grade (optional)',
      'agri_computed_cost_preview': 'Computed cost',
      'agri_reports_title': 'Crop Reports',
      'agri_planning_tab': 'Planning',
      'agri_cost_yield_tab': 'Cost & Yield',
      'agri_from_date_label': 'From',
      'agri_to_date_label': 'To',
      'agri_all_farms': 'All farms',
      'agri_all_varieties': 'All varieties',
      'agri_overdue_only': 'Overdue',
      'agri_pending_only': 'Upcoming',
      'agri_total_items': 'Total',
      'agri_by_farm': 'By farm',
      'agri_no_pending_items': 'Nothing due in this range',
      'agri_group_by_label': 'Group by',
      'agri_generate_report': 'Generate',
      'agri_export_excel': 'Export as Excel',
      'agri_input_cost_col': 'Input Cost',
      'agri_labor_cost_col': 'Labor Cost',
      'agri_total_cost_col': 'Total Cost',
      'agri_yield_col': 'Yield',
      'agri_cost_per_kg_col': 'Cost/kg',
      'agri_grand_total': 'Grand Total',
      'agri_no_report_yet': 'Pick a date range and tap Generate',
      'agri_select_date_range': 'Select a date range first',
      'sector_picker_title': 'Which side are you working in?',
      'sector_picker_subtitle':
          'You have access to both — pick one for now. You can switch anytime from the dashboard.',
      'sector_factory_label': 'Factory',
      'sector_factory_desc':
          'Electricity, machines, outward register, payroll and daily reports',
      'sector_agriculture_label': 'Agriculture',
      'sector_agriculture_desc':
          'Farm attendance, tractor, crop planning and reports',
      'sector_switch_title': 'Switch sector',
    },
    'mr': {
      'save': 'जतन करा',
      'cancel': 'रद्द करा',
      'delete': 'हटवा',
      'edit': 'संपादित करा',
      'loading': 'लोड होत आहे…',
      'search': 'शोधा',
      'language': 'भाषा',
      'select_language': 'भाषा निवडा',
      'english': 'English',
      'marathi': 'मराठी',
      'logout': 'बाहेर पडा',
      'app_tagline': 'दैनंदिन अहवाल आणि नोंदणी',
      'sign_in': 'साइन इन करा',
      'enter_credentials': 'सुरू ठेवण्यासाठी तुमचा तपशील टाका',
      'username_label': 'वापरकर्ता नाव',
      'password_label': 'पासवर्ड',
      'enter_credentials_error': 'कृपया तुमचे वापरकर्ता नाव आणि पासवर्ड टाका.',
      'cannot_connect_error':
          'सर्व्हरशी कनेक्ट होऊ शकत नाही. तुमचे कनेक्शन तपासा.',
      'invalid_credentials_error': 'चुकीचे क्रेडेन्शियल्स. पुन्हा प्रयत्न करा.',
      'welcome_back': 'पुन्हा स्वागत आहे',
      'section_daily_entries': 'दैनंदिन नोंदी',
      'section_reports_analytics': 'अहवाल आणि विश्लेषण',
      'section_payroll': 'पगार',
      'section_farm_operations': 'शेती कामकाज',
      'section_administrative': 'प्रशासकीय',
      'section_administration': 'प्रशासन',

      // Farm Attendance — entry screen
      'fa_title': 'शेत मजूर हजेरी',
      'fa_reports_tooltip': 'अहवाल',
      'fa_workers_available_today': 'आज उपलब्ध मजूर',
      'fa_male': 'पुरुष',
      'fa_female': 'महिला',
      'fa_male_full': 'पुरुष',
      'fa_female_full': 'महिला',
      'fa_permanent_full': 'कायम',
      'fa_total_workers_available': 'एकूण उपलब्ध मजूर',
      'fa_male_short': 'पुरुष',
      'fa_female_short': 'महिला',
      'fa_set': 'सेट करा',
      'fa_assigned': 'नेमलेले',
      'fa_fully_assigned': 'पूर्ण नेमणूक झाली',
      'fa_add_batch': 'बॅच जोडा',
      'fa_batch_desc':
          'एक शेत + एक कामाचा प्रकार + सुचवलेला दर, नंतर ते काम करणारे सर्व निवडा.',
      'fa_farm': 'शेत',
      'fa_work_type': 'कामाचा प्रकार',
      'fa_suggested_rate': 'या बॅचसाठी सुचवलेला दर (₹)',
      'fa_select_workers': 'मजूर निवडा',
      'fa_per_worker_day_rate': 'प्रत्येक मजुरासाठी दिवस आणि दर',
      'fa_day': 'दिवस',
      'fa_rate_rupee': 'दर ₹',
      'fa_save_batch': 'बॅच जतन करा',
      'fa_saving': 'जतन होत आहे…',
      'fa_entries_for': 'साठी नोंदी',
      'fa_total': 'एकूण',
      'fa_no_attendance_today': 'या तारखेसाठी अजून हजेरी नोंदवलेली नाही',
      'fa_search_workers': 'मजूर शोधा…',
      'fa_no_workers_match': 'कोणताही मजूर जुळत नाही',
      'fa_gender_not_set': 'लिंग नोंदवलेले नाही',
      'fa_selected': 'निवडले',
      'fa_type_to_search': 'शोधण्यासाठी टाइप करा',
      'fa_delete_entry_title': 'नोंद हटवायची का?',
      'fa_delete_entry_confirm': 'ही हजेरी नोंद कायमची हटवली जाईल.',
      'fa_day_field_hint': 'दिवस (1, 0.5, 1.5, ...)',
      'fa_rate_rupee_label': 'दर (₹)',
      'fa_err_headcount': 'वैध पुरुष आणि महिला मजूर संख्या टाका (0 किंवा अधिक)',
      'fa_err_server': 'सर्व्हरशी संपर्क होऊ शकला नाही',
      'fa_err_select_farm': 'या बॅचसाठी शेत निवडा',
      'fa_err_select_worker': 'किमान एक मजूर निवडा',
      'fa_workers_saved': 'मजूर जतन केले',
      'fa_saved': 'जतन केले',
      'fa_skipped': 'वगळले (या तारीख/शेत/कामासाठी आधीच नोंदवलेले)',
      'fa_status_calendar_tooltip': 'स्थिती दिनदर्शिका',
      'fa_mark_via_face': 'चेहऱ्याद्वारे नोंदवा',
      'fa_add_worker': 'मजूर जोडा',
      'fa_today_present': 'आज हजर',
      'fa_expected_total_wage': 'अपेक्षित एकूण मजुरी',
      'fa_submitting': 'सादर करत आहे…',
      'fa_review_submit_attendance': 'हजेरी तपासा आणि सादर करा',
      'fa_all': 'सर्व',
      'fa_status_pending_attendance':
          'हजेरी सादर केली — प्रशासकाच्या मंजुरीच्या प्रतीक्षेत',
      'fa_status_approved_alloc_approved': 'हजेरी मंजूर · काम वाटप मंजूर',
      'fa_status_approved_alloc_pending':
          'हजेरी मंजूर · काम वाटप मंजुरीच्या प्रतीक्षेत',
      'fa_status_approved_ready': 'हजेरी मंजूर — काम वाटपासाठी तयार',
      'fa_status_returned': 'दुरुस्तीसाठी परत पाठवले',
      'fa_approve': 'मंजूर करा',
      'fa_reject': 'नाकारा',
      'fa_go_to_work_allocation': 'काम वाटपाकडे जा',
      'fa_add': 'जोडा',
      'fa_review_present_workers': 'हजर मजुरांचे पुनरावलोकन करा',
      'fa_confirm_submit': 'पुष्टी करा आणि सादर करा',
      'fa_reject_attendance_title': 'हजेरी नाकारा',
      'fa_reject_attendance_hint': 'दुरुस्तीसाठी हे परत का पाठवले जात आहे?',
      'fa_confirm': 'पुष्टी करा',
      'fa_err_save_headcount': 'संख्या जतन करण्यात अयशस्वी',
      'fa_err_submit_attendance': 'हजेरी सादर करण्यात अयशस्वी',
      'fa_err_record_decision': 'निर्णय नोंदवण्यात अयशस्वी',
      'fa_already_marked_present': 'आधीच हजर म्हणून नोंदवले आहे',
      'fa_marked_via_face': 'चेहरा ओळखीद्वारे हजर म्हणून नोंदवले',
      'fa_attendance_submitted': 'हजेरी मंजुरीसाठी सादर केली',
      'fa_worker_added': 'मजूर जोडला',
      'fa_step_headcount': 'पायरी १ / ५ — आजची संख्या सेट करा',
      'fa_step_attendance_pending': 'पायरी २ / ५ — हजेरी मंजुरीच्या प्रतीक्षेत',
      'fa_step_attendance_returned':
          'पायरी २ / ५ — हजेरी परत पाठवली, दुरुस्ती आवश्यक',
      'fa_step_attendance_approved':
          'पायरी ३ / ५ — हजेरी मंजूर, काम वाटपासाठी तयार',
      'fa_step_allocation_pending':
          'पायरी ४ / ५ — काम वाटप मंजुरीच्या प्रतीक्षेत',
      'fa_step_allocation_returned':
          'पायरी ४ / ५ — काम वाटप परत पाठवले, दुरुस्ती आवश्यक',
      'fa_step_complete': 'पायरी ५ / ५ — पूर्ण',
      'fa_selected_label': 'निवडलेले',
      'fa_wa_title': 'काम वाटप',
      'fa_wa_must_approve_first':
          'काम वाटप करण्यापूर्वी आजची हजेरी मंजूर असणे आवश्यक आहे.',
      'fa_wa_present_to_allocate': 'हजर मजूर वाटप करायचे आहेत.',
      'fa_wa_expected_total_suffix': 'अपेक्षित एकूण',
      'fa_wa_status_pending':
          'काम वाटप सादर केले — प्रशासकाच्या मंजुरीच्या प्रतीक्षेत',
      'fa_wa_status_approved': 'काम वाटप मंजूर — अंतिम',
      'fa_wa_tasks': 'कामे',
      'fa_wa_allocated_suffix': 'वाटप झाले',
      'fa_wa_task_number': 'काम',
      'fa_wa_add_more_workers_to_task': 'कामात अधिक मजूर जोडा',
      'fa_wa_assign_task_select_workers': 'काम नेमा — मजूर निवडा',
      'fa_wa_add_new_single_task': 'नवीन काम जोडा',
      'fa_wa_multi_task_remaining': 'बहु-काम — उर्वरित मजूर',
      'fa_wa_multi_task_hint':
          'प्रत्येक मजुराला एकापेक्षा जास्त शेत + कामाच्या प्रकारात विभागता येते — आणखी जोडण्यासाठी + दाबा.',
      'fa_wa_saving': 'जतन करत आहे…',
      'fa_wa_save_all_allocations': 'सर्व वाटप जतन करा',
      'fa_wa_this_morning_suffix': 'आज सकाळी',
      'fa_wa_subtotal': 'उपबेरीज',
      'fa_wa_assign_task': 'काम नेमा',
      'fa_wa_edit_tasks': 'कामे संपादित करा',
      'fa_wa_remarks_header': 'शेरा — सकाळची रक्कम वि. वाटप',
      'fa_wa_allocations_header': 'वाटप',
      'fa_wa_total_prefix': 'एकूण',
      'fa_wa_remark_same': 'सकाळप्रमाणेच',
      'fa_wa_remark_excess': 'जास्त',
      'fa_wa_remark_less': 'कमी',
      'fa_wa_remark_unallocated': 'वाटप केले नाही',
      'fa_wa_remark_no_morning': 'सकाळची रक्कम नोंदवलेली नाही',
      'fa_wa_break_attendance_note_prefix': 'तुटलेली हजेरी',
      'fa_wa_allocated_so_far_prefix': 'आतापर्यंत वाटप',
      'fa_wa_matches_expected_suffix': 'अपेक्षित',
      'fa_wa_expected_suffix': 'शी जुळते',
      'fa_wa_excess_over_suffix': 'पेक्षा जास्त',
      'fa_wa_less_than_suffix': 'पेक्षा कमी',
      'fa_wa_reject_title': 'काम वाटप नाकारा',
      'fa_wa_reject_hint': 'दुरुस्तीसाठी हे परत का पाठवले जात आहे?',
      'fa_wa_err_still_need_task': 'हजर मजुरांना अजून काम नेमलेले नाही:',
      'fa_wa_err_add_task_group': 'किमान एक काम गट जोडा',
      'fa_wa_did_not_work': 'काम केले नाही',
      'fa_wa_did_not_work_hint':
          'आज सकाळी उपस्थित नोंदवले होते पण प्रत्यक्षात काम केले नाही — आजच्या उपस्थिती संख्येतून पूर्णपणे वगळले जाईल, आणि मजुरी दिली जाणार नाही.',
      'fa_wa_add_missed_worker': 'चुकलेला मजूर जोडा',
      'fa_wa_add_missed_worker_hint':
          'ज्या मजुराने आज प्रत्यक्षात काम केले पण मूळ हजेरीत सुटला त्याच्यासाठी. आजच्या उपस्थिती संख्येत जोडले जाईल आणि थेट मजुरी दिली जाईल — लगेच अंतिम, पुढील मंजुरीची गरज नाही.',
      'fa_wa_worker_label': 'मजूर',
      'fa_wa_farm_label': 'शेत',
      'fa_wa_work_type_optional_label': 'कामाचा प्रकार (ऐच्छिक)',
      'fa_wa_reason_label': 'कारण',
      'fa_wa_err_save_allocation': 'वाटप जतन करण्यात अयशस्वी',
      'fa_wa_break_attendance_title_prefix': 'तुटलेली हजेरी',
      'fa_wa_break_hint':
          'दिवस संपण्यापूर्वी निघाले? रक्कम कमी करा आणि कारण नोंदवा.',
      'fa_wa_reduced_amount_label': 'कमी केलेली रक्कम (₹)',
      'fa_wa_reason_hint': 'कारण (उदा. दुपारी १ वाजता निघाले — अस्वस्थ)',
      'fa_wa_apply': 'लागू करा',
      'fa_wa_err_add_farm': 'या मजुरासाठी किमान एक शेत जोडा',
      'fa_wa_err_amount_every_line': 'प्रत्येक कामाच्या ओळीसाठी रक्कम टाका',
      'fa_wa_assign_task_title_prefix': 'काम नेमा',
      'fa_wa_work_type_add_another_header':
          'कामाचा प्रकार — आणखी जोडण्यासाठी + दाबा',
      'fa_wa_farm_dropdown_label': 'शेत',
      'fa_wa_work_type_dropdown_label': 'कामाचा प्रकार',
      'fa_wa_rate_label': 'दर ₹',
      'fa_wa_enter_amount_hint': 'रक्कम टाका',
      'fa_wa_break_short': 'तुटले',
      'fa_wa_note_prefix': 'टीप',
      'fa_wa_add_another_work_type': 'आणखी कामाचा प्रकार जोडा',
      'fa_wa_remove': 'काढा',
      'fa_wa_workers_for_this_task': 'या कामासाठी मजूर',
      'fa_wa_set_this_morning_hint': 'आज सकाळी सेट केले — प्रशासक बदलू शकतो',
      'fa_wa_break_attendance_long': 'तुटलेली हजेरी',
      'fa_wa_err_select_farm': 'शेत निवडा',
      'fa_wa_err_select_one_worker': 'किमान एक मजूर निवडा',
      'fa_wa_err_amount_every_worker':
          'प्रत्येक निवडलेल्या मजुरासाठी रक्कम टाका',
      'fa_wa_save_this_task_group': 'हा काम गट जतन करा',
      'fa_wa_task_group_default_title': 'काम गट',
      'fa_wa_task1_farm_workers_title': 'काम १ — शेत आणि मजूर',
      'fa_cal_title': 'हजेरी स्थिती दिनदर्शिका',
      'fa_cal_err_load': 'दिनदर्शिका लोड करण्यात अयशस्वी',
      'fa_cal_mon': 'सोम',
      'fa_cal_tue': 'मंगळ',
      'fa_cal_wed': 'बुध',
      'fa_cal_thu': 'गुरु',
      'fa_cal_fri': 'शुक्र',
      'fa_cal_sat': 'शनि',
      'fa_cal_sun': 'रवि',
      'fa_cal_legend': 'सूची',
      'fa_cal_legend_fully_approved':
          'पूर्णपणे मंजूर — हजेरी आणि काम वाटप दोन्ही मंजूर',
      'fa_cal_legend_partially_approved':
          'अंशतः मंजूर — हजेरी मंजूर, वाटप अजून नाही',
      'fa_cal_legend_not_approved':
          'मंजूर नाही — हजेरी अजूनही प्रलंबित किंवा परत पाठवली',
      'fa_cal_legend_no_data': 'या तारखेसाठी हजेरी नोंदवलेली नाही',

      // Farm Attendance — reports screen
      'fa_reports_title': 'हजेरी अहवाल',
      'fa_worker_wage_report_title': 'मजूर वेतन अहवाल',
      'fa_worker_wage_report_desc':
          'प्रत्येक मजुरासाठी एक ओळ, प्रत्येक तारखेचा दिवस / रक्कम / शेत / कामाचा प्रकार गट, आणि मजुराची एकूण बेरीज.',
      'fa_gender_split_report_title': 'मजूर वेतन अहवाल — पुरुष/स्त्री विभागणी',
      'fa_gender_split_report_desc':
          'प्रत्येक मजुरासाठी एक ओळ, प्रत्येक तारखेसाठी एक स्तंभ, मजुराची एकूण बेरीज — पुरुष आणि स्त्री अशा दोन स्वतंत्र तक्त्यांमध्ये, प्रत्येकाची स्वतःची उपबेरीज.',
      'fa_from': 'पासून',
      'fa_to': 'पर्यंत',
      'fa_generate_excel_report': 'एक्सेल अहवाल तयार करा',
      'fa_generating': 'तयार होत आहे…',
      'fa_report_downloaded': 'अहवाल डाउनलोड झाला',
      'fa_saved_label': 'जतन केले',
      'fa_dynamic_report_title': 'डायनॅमिक अहवाल (स्लाइस आणि डाइस)',
      'fa_dynamic_report_desc':
          'गटीकरण स्तर क्रमाने निवडा — वगळण्यासाठी कोणताही "काहीही नाही" ठेवा. बेरीज दिवस आणि वेतन आहे.',
      'fa_selection_1': 'पहिली निवड',
      'fa_selection_2': 'दुसरी निवड',
      'fa_selection_3': 'तिसरी निवड',
      'fa_generate': 'तयार करा',
      'fa_export_to_excel': 'एक्सेलमध्ये निर्यात करा',
      'fa_exporting': 'निर्यात होत आहे…',
      'fa_no_entries_range':
          'या तारीख कालावधीसाठी कोणत्याही हजेरी नोंदी सापडल्या नाहीत.',
      'fa_total_days_col': 'एकूण दिवस',
      'fa_total_wage_col': 'एकूण वेतन',
      'fa_entries_col': 'नोंदी',
      'fa_grand_total': 'एकूण बेरीज',
      'fa_none': 'काहीही नाही',
      'fa_worker': 'मजूर',
      'fa_gender': 'लिंग',

      // Farm Attendance — admin masters screen
      'fa_setup_title': 'शेत हजेरी सेटअप',
      'fa_farms_tab': 'शेते',
      'fa_work_types_tab': 'कामाचे प्रकार',
      'fa_workers_tab': 'मजूर',
      'fa_add_farm': 'शेत जोडा',
      'fa_edit_farm': 'शेत संपादित करा',
      'fa_farm_name_label': 'शेताचे नाव',
      'fa_location_optional_label': 'ठिकाण (ऐच्छिक)',
      'fa_total_area_label': 'एकूण शेत क्षेत्र (एकर)',
      'fa_add_work_type': 'कामाचा प्रकार जोडा',
      'fa_rename_work_type': 'कामाच्या प्रकाराचे नाव बदला',
      'fa_work_type_name_hint': 'कामाच्या प्रकाराचे नाव',
      'fa_add_farm_worker': 'शेत मजूर जोडा',
      'fa_edit_farm_worker': 'शेत मजूर संपादित करा',
      'fa_worker_name_label': 'मजुराचे नाव',
      'fa_daily_wage_label': 'दैनिक वेतन (₹)',
      'fa_home_farm_label': 'मूळ शेत',
      'fa_phone_optional_label': 'फोन (ऐच्छिक)',
      'fa_no_farms_yet': 'अजून कोणतेही शेत नाही — जोडण्यासाठी + दाबा',
      'fa_no_work_types_yet': 'अजून कामाचे प्रकार नाहीत — जोडण्यासाठी + दाबा',
      'fa_no_farm_workers_yet': 'अजून शेत मजूर नाहीत — जोडण्यासाठी + दाबा',
      // Farm Tractor
      'ft_setup_title': 'फार्म ट्रॅक्टर सेटअप',
      'ft_tractors_tab': 'ट्रॅक्टर्स',
      'ft_rates_tab': 'दर',
      'ft_add_tractor': 'ट्रॅक्टर जोडा',
      'ft_edit_tractor': 'ट्रॅक्टर संपादित करा',
      'ft_tractor_name_label': 'ट्रॅक्टरचे नाव',
      'ft_registration_label': 'नोंदणी क्रमांक (ऐच्छिक)',
      'ft_hp_label': 'एचपी (ऐच्छिक)',
      'ft_no_tractors_yet': 'अजून ट्रॅक्टर नाहीत — जोडण्यासाठी + दाबा',
      'ft_no_rates_yet': 'अजून दर सेट केलेले नाहीत — जोडण्यासाठी + दाबा',
      'ft_set_rate': 'दर सेट करा',
      'ft_tractor_label': 'ट्रॅक्टर',
      'ft_work_type_label': 'कामाचा प्रकार',
      'ft_billing_unit_label': 'प्रति आकारले',
      'ft_rate_label': 'दर (₹)',
      'ft_effective_from_label': 'पासून लागू',
      'ft_screen_title': 'फार्म ट्रॅक्टर',
      'ft_diesel_log_tooltip': 'डिझेल नोंद',
      'ft_setup_tooltip': 'सेटअप',
      'ft_assign_work': 'काम नेमून द्या',
      'ft_farm_label': 'शेत',
      'ft_hour_start_label': 'तास मीटर सुरुवात (ऐच्छिक)',
      'ft_notes_label': 'टीप (ऐच्छिक)',
      'ft_select_required': 'ट्रॅक्टर, शेत आणि कामाचा प्रकार निवडा',
      'ft_work_assigned': 'काम नेमले',
      'ft_failed_assign': 'काम नेमण्यात अयशस्वी',
      'ft_in_progress': 'सुरू आहे',
      'ft_completed': 'पूर्ण झाले',
      'ft_no_completed_work': 'या तारखेसाठी कोणतेही पूर्ण झालेले काम नाही',
      'ft_tap_to_complete': 'पूर्ण करण्यासाठी टॅप करा',
      'ft_hour_meter_end_label': 'तास मीटर शेवट',
      'ft_started_at': 'येथे सुरू झाले',
      'ft_quantity_label': 'प्रमाण',
      'ft_billing_choice_title': 'हे काम कसे आकारले जाते?',
      'ft_complete_button': 'पूर्ण करा',
      'ft_work_completed': 'काम पूर्ण झाले',
      'ft_failed_complete': 'पूर्ण करण्यात अयशस्वी',
      'ft_diesel_title': 'डिझेल नोंद',
      'ft_add_fillup': 'डिझेल भरणा जोडा',
      'ft_date_label': 'तारीख',
      'ft_liters_label': 'भरलेले लिटर',
      'ft_cost_label': 'खर्च (₹, ऐच्छिक)',
      'ft_hour_meter_reading_label': 'तास मीटर रीडिंग (ऐच्छिक)',
      'ft_hour_meter_helper': 'इंधन-सरासरी गणनेसाठी आवश्यक',
      'ft_average_fuel_use': 'सरासरी इंधन वापर',
      'ft_fillup_history': 'भरणा इतिहास',
      'ft_no_diesel_logs': 'अजून डिझेल नोंदी नाहीत — जोडण्यासाठी + दाबा',
      'ft_no_tractors_setup_first':
          'अजून ट्रॅक्टर नाहीत — आधी सेटअपमध्ये एक जोडा',
      // Crop Planning (agri)
      'agri_crop_masters_title': 'पीक मास्टर्स',
      'agri_crops_tab': 'पिके',
      'agri_varieties_tab': 'जाती',
      'agri_agronomy_setup_title': 'कृषी सेटअप',
      'agri_orchard_blocks_tab': 'फळबाग विभाग',
      'agri_stage_templates_tab': 'टप्पा साचे',
      'agri_spray_templates_tab': 'फवारणी साचे',
      'agri_add_crop': 'पीक जोडा',
      'agri_edit_crop': 'पीक संपादित करा',
      'agri_crop_name_label': 'पिकाचे नाव',
      'agri_category_label': 'श्रेणी (ऐच्छिक)',
      'agri_crop_type_label': 'पिकाचा प्रकार',
      'agri_seasonal': 'हंगामी',
      'agri_perennial': 'बहुवर्षीय',
      'agri_add_variety': 'जात जोडा',
      'agri_edit_variety': 'जात संपादित करा',
      'agri_variety_name_label': 'जातीचे नाव',
      'agri_source_notes_label': 'स्त्रोत टीप (ऐच्छिक)',
      'agri_maturity_days_label': 'परिपक्वता दिवस (ऐच्छिक)',
      'agri_std_yield_label': 'प्रति रोप प्रमाणित उत्पादन (ऐच्छिक)',
      'agri_yield_unit_label': 'उत्पादन एकक (ऐच्छिक)',
      'agri_add_orchard_block': 'फळबाग विभाग जोडा',
      'agri_edit_orchard_block': 'फळबाग विभाग संपादित करा',
      'agri_farm_label': 'शेत',
      'agri_variety_label': 'जात',
      'agri_planting_date_label': 'लागवड तारीख',
      'agri_no_of_trees_label': 'झाडांची संख्या (ऐच्छिक)',
      'agri_area_acre_label': 'क्षेत्र (एकर, ऐच्छिक)',
      'agri_status_label': 'स्थिती',
      'agri_add_stage_template': 'टप्पा साचा जोडा',
      'agri_edit_stage_template': 'टप्पा साचा संपादित करा',
      'agri_stage_name_label': 'टप्प्याचे नाव',
      'agri_trigger_type_label': 'ट्रिगर प्रकार',
      'agri_trigger_days_start_label': 'ट्रिगर दिवस — सुरुवात',
      'agri_trigger_days_end_label': 'ट्रिगर दिवस — शेवट',
      'agri_tree_age_bracket_label': 'झाडाचे वय गट (ऐच्छिक)',
      'agri_notes_label': 'टीप (ऐच्छिक)',
      'agri_add_spray_template': 'फवारणी साचा जोडा',
      'agri_edit_spray_template': 'फवारणी साचा संपादित करा',
      'agri_trigger_days_label': 'ट्रिगर दिवस',
      'agri_activity_type_label': 'क्रियाकलाप प्रकार',
      'agri_product_suggestion_label': 'उत्पादन सूचना (ऐच्छिक)',
      'agri_dose_per_acre_label': 'प्रति एकर मात्रा',
      'agri_dose_per_tree_label': 'प्रति झाड मात्रा',
      'agri_dose_unit_label': 'मात्रा एकक (ऐच्छिक)',
      'agri_sequence_order_label': 'क्रम (ऐच्छिक)',
      'agri_no_crops_yet': 'अजून पिके नाहीत — जोडण्यासाठी + दाबा',
      'agri_no_varieties_yet': 'अजून जाती नाहीत — जोडण्यासाठी + दाबा',
      'agri_no_orchard_blocks_yet':
          'अजून फळबाग विभाग नाहीत — जोडण्यासाठी + दाबा',
      'agri_no_stage_templates_yet':
          'अजून टप्पा साचे नाहीत — जोडण्यासाठी + दाबा',
      'agri_no_spray_templates_yet':
          'अजून फवारणी साचे नाहीत — जोडण्यासाठी + दाबा',
      'agri_saved': 'जतन झाले',
      'agri_failed_save': 'जतन करण्यात अयशस्वी',
      'agri_cycles_title': 'पीक चक्रे',
      'agri_add_sowing_plan': 'नवीन पेरणी योजना',
      'agri_add_orchard_cycle': 'नवीन फळबाग चक्र',
      'agri_season_label': 'हंगाम',
      'agri_sowing_date_label': 'पेरणी तारीख',
      'agri_area_sown_label': 'पेरलेले क्षेत्र (एकर, ऐच्छिक)',
      'agri_spacing_section_header': 'ओळ आणि रोप अंतर (ऐच्छिक)',
      'agri_row_spacing_label': 'ओळ ते ओळ अंतर',
      'agri_plant_spacing_label': 'रोप ते रोप अंतर',
      'agri_unit_ft': 'फूट',
      'agri_unit_in': 'इंच',
      'agri_unit_cm': 'सेंटीमीटर',
      'agri_row_arrangement_label': 'ओळींची रचना',
      'agri_arrangement_uniform': 'एकसमान',
      'agri_arrangement_paired': 'जोडी ओळी',
      'agri_intra_pair_label': 'जोडीतील अंतर',
      'agri_inter_pair_label': 'जोड्यांमधील अंतर',
      'agri_add_intercrop_button': 'आंतरपीक जोडा',
      'agri_add_intercrop_title': 'आंतरपीक जोडा',
      'agri_intercrop_hint':
          'ज्या शेतात मुख्य पिकासोबत दुसरे पीक ठराविक ओळींच्या पद्धतीने पेरले जाते त्यासाठी (उदा. प्रत्येक ६ ओळी सोयाबीन नंतर २ ओळी तूर).',
      'agri_intercrop_variety_label': 'आंतरपीक जात',
      'agri_main_rows_per_cycle_label': 'मुख्य पिकाच्या ओळी प्रति चक्र',
      'agri_intercrop_rows_per_cycle_label': 'आंतरपिकाच्या ओळी प्रति चक्र',
      'agri_shared_area_label': 'या शेताचे एकूण प्रत्यक्ष क्षेत्र (एकर)',
      'agri_intercrop_added_msg':
          'आंतरपीक जोडले — दोन्ही पिकांसाठी क्षेत्र पुन्हा मोजले',
      'agri_intercrop_group_header': 'यासोबत आंतरपीक',
      'agri_calculated_area_note': 'ओळींच्या पद्धतीवरून क्षेत्र आपोआप मोजले',
      'agri_orchard_block_label': 'फळबाग विभाग',
      'agri_cycle_year_label': 'चक्र वर्ष',
      'agri_bahar_name_label': 'बहार नाव (ऐच्छिक)',
      'agri_flowering_start_label': 'फुलोरा सुरुवात तारीख (ऐच्छिक)',
      'agri_no_cycles_yet': 'अजून पीक चक्रे नाहीत — सुरू करण्यासाठी + दाबा',
      'agri_schedule_generated': 'चक्र तयार झाले — वेळापत्रक तयार केले',
      'agri_calendar_title': 'पीक दिनदर्शिका',
      'agri_overdue_section': 'थकीत',
      'agri_pending_section': 'आगामी',
      'agri_not_scheduled_section': 'अजून वेळापत्रक नाही',
      'agri_done_section': 'पूर्ण झाले',
      'agri_skipped_section': 'वगळले',
      'agri_waiting_on': 'प्रतीक्षेत',
      'agri_mark_complete': 'पूर्ण म्हणून चिन्हांकित करा',
      'agri_skip_action': 'वगळा — झाले नाही / गरज नाही',
      'agri_operation_date_label': 'प्रत्यक्षात केल्याची तारीख',
      'agri_cost_label': 'खर्च (₹)',
      'agri_worker_label': 'मजूर (ऐच्छिक)',
      'agri_skip_remarks_label': 'हे का वगळले जात आहे?',
      'agri_delay_days': 'दिवस उशीर',
      'agri_early_days': 'दिवस लवकर',
      'agri_on_time': 'वेळेवर',
      'agri_log_labor': 'मजूर नोंदवा',
      'agri_log_harvest': 'काढणी नोंदवा',
      'agri_payment_mode_label': 'देय पद्धत',
      'agri_daily': 'रोजंदारी',
      'agri_piece_rate': 'तुकडा दर',
      'agri_days_worked_label': 'कामाचे दिवस',
      'agri_daily_wage_label': 'रोजंदारी (₹)',
      'agri_qty_harvested_label': 'काढणी प्रमाण (किलो)',
      'agri_rate_per_kg_label': 'प्रति किलो दर (₹)',
      'agri_harvest_date_label': 'काढणी तारीख',
      'agri_total_yield_label': 'एकूण उत्पादन प्रमाण',
      'agri_unit_label': 'एकक',
      'agri_quality_grade_label': 'गुणवत्ता दर्जा (ऐच्छिक)',
      'agri_computed_cost_preview': 'गणना केलेला खर्च',
      'agri_reports_title': 'पीक अहवाल',
      'agri_planning_tab': 'नियोजन',
      'agri_cost_yield_tab': 'खर्च आणि उत्पादन',
      'agri_from_date_label': 'पासून',
      'agri_to_date_label': 'पर्यंत',
      'agri_all_farms': 'सर्व शेत',
      'agri_all_varieties': 'सर्व जाती',
      'agri_overdue_only': 'थकीत',
      'agri_pending_only': 'आगामी',
      'agri_total_items': 'एकूण',
      'agri_by_farm': 'शेतानुसार',
      'agri_no_pending_items': 'या कालावधीत काहीही प्रलंबित नाही',
      'agri_group_by_label': 'गटानुसार',
      'agri_generate_report': 'तयार करा',
      'agri_export_excel': 'एक्सेल म्हणून निर्यात करा',
      'agri_input_cost_col': 'निविष्ठा खर्च',
      'agri_labor_cost_col': 'मजूर खर्च',
      'agri_total_cost_col': 'एकूण खर्च',
      'agri_yield_col': 'उत्पादन',
      'agri_cost_per_kg_col': 'खर्च/किलो',
      'agri_grand_total': 'एकूण बेरीज',
      'agri_no_report_yet': 'तारीख श्रेणी निवडा आणि तयार करा दाबा',
      'agri_select_date_range': 'आधी तारीख श्रेणी निवडा',
      'sector_picker_title': 'तुम्ही कोणत्या विभागात काम करत आहात?',
      'sector_picker_subtitle':
          'तुम्हाला दोन्हीचा प्रवेश आहे — सध्यासाठी एक निवडा. डॅशबोर्डवरून कधीही बदलू शकता.',
      'sector_factory_label': 'कारखाना',
      'sector_factory_desc':
          'वीज, यंत्रे, आउटवर्ड रजिस्टर, पगार आणि दैनिक अहवाल',
      'sector_agriculture_label': 'शेती',
      'sector_agriculture_desc': 'शेत हजेरी, ट्रॅक्टर, पीक नियोजन आणि अहवाल',
      'sector_switch_title': 'विभाग बदला',
    },
  };

  // Module tile translations, keyed by kModuleDefinitions' `key`.
  // Only Marathi needs entries here — English already comes from
  // kModuleDefinitions itself as the fallback.
  static const Map<String, Map<String, Map<String, String>>> _moduleStrings = {
    'mr': {
      'electricity': {
        'label': 'वीज मीटर रीडिंग',
        'description': 'दैनंदिन वीज मीटर रीडिंग सबमिट करा आणि पहा',
      },
      'tractor': {
        'label': 'ट्रॅक्टर तास',
        'description': 'दैनंदिन ट्रॅक्टर मीटर रीडिंग आणि तास सबमिट करा',
      },
      'labour': {
        'label': 'मजूर व्यवस्थापन',
        'description': 'मजुरांच्या हजेरीच्या नोंदी जोडा, संपादित करा आणि पहा',
      },
      'farm_tractor': {
        'label': 'फार्म ट्रॅक्टर',
        'description':
            'ट्रॅक्टरचे शेतातील काम नेमून द्या आणि तास, डिझेल व बिलिंगची नोंद ठेवा',
      },
      'factory': {
        'label': 'कारखाना चालू तास',
        'description': 'यंत्र सुरू/बंद वेळ आणि डाउनटाइम नोंदवा',
      },
      'farm_attendance': {
        'label': 'शेत मजूर हजेरी',
        'description': 'शेतमजुरांची दैनंदिन हजेरी आणि मजुरी नोंदवा',
      },
      'daily_report': {
        'label': 'दैनंदिन अहवाल',
        'description': 'दैनंदिन अहवाल तयार करा',
      },
      'payroll': {
        'label': 'पगार',
        'description': 'कामगारांचे वेतन आणि कपात व्यवस्थापित करा',
      },
      'mandi_prices': {
        'label': 'बाजारभाव',
        'description': 'आजचे बाजार समितीचे भाव, कल आणि विक्रीची योग्य वेळ',
      },
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'mr'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
