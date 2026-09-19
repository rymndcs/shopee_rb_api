# frozen_string_literal: true

module ShopeeRbApi
  # Classifies Shopee's `error` / `message` pair into an ApiError subclass.
  #
  # Built from the error_list and common_error_list of every endpoint doc this gem calls
  # (https://open.shopee.com/documents/v2/<api_name>, pulled 2026-09-19; test/fixtures/error_list.json holds them all).
  # Shopee overloads some codes: `error_auth` also carries business rejections and `error_param` also carries
  # signature failures, so the MESSAGE rules come first. A code this table does not name raises plain ApiError:
  # the gem never guesses a subclass.
  module ErrorTable
    # [code, message pattern or nil, class name]. The first matching rule wins.
    MESSAGE_RULES = [
      ["error_param", /no sign in query|no timestamp|timestamp is (expired|invalid)|invalid timestamp/i,
       :SignatureError],
      ["error_param", /\AInvalid partner_id\.\z/, :AppCredentialsError],
      ["error_param", /There is no (partner_id|access_token|shop_id) in query|should be an integer between/i,
       :RequestError],
      ["error_param", /request path is incorrect|request not from gateway|\[Gateway\] illegal request/i, :RequestError],
      ["error_auth", /partner_id is invalid|App is deleted|permissions for authorizations have been restricted/i,
       :AppCredentialsError],
      ["error_auth", /Invalid access_token|Invalid partner_id or shopid/i, :AuthenticationError],
      ["error_auth", /No permission to current api|registered phone number of your shop is abnormal/i,
       :PermissionError],
      ["error_auth", /System error/i, :ServerError],
      ["error_server", /normal stock must be equal to 0/i, :BusinessError],
      ["error_inner", /Invalid stock location ID/i, :BusinessError],
      [nil, /Interal error, please contact openapi team/i, :ServerError]
    ].freeze

    CODES = {
      SignatureError: %w[error_sign],
      AppCredentialsError: %w[invalid_partner_id error_partner_key_expired error_api_call_restricted],
      AuthenticationError: %w[
        invalid_acceess_token shop_no_linked partner_shop_no_link merchant_no_linked supplier_no_linked
        shop_access_expired merchant_access_expired supplier_access_expired refresh_token_expired
        error_shop_refresh_token error_merchant_refresh_token invalid_code invalid_shop_id invalid_main_acount_id
      ],
      PermissionError: %w[
        error_api_permission error_ashop_api_permission error_kyc_auth shop_banned source_ip_undeclared
        error_perm_non_admin error_permission error_seller_under_penalty error_busi_invalid_shop_status
        error_busi_invalid_account_status
      ],
      RateLimitError: %w[error_rate_limit],
      QuotaExceededError: %w[error_limit],
      ServerError: %w[
        error_server error_inner error_system_busy error_network error_marshal error_get_shop_fail
        error_busi_add_item_failed error_busi_update_item_failed error_busi_update_global_item_failed
        error_update_price_fail error_unlist_item_failed error_unknown
      ],
      RequestError: %w[api_suspended error_not_found],
      BusinessError: %w[
        error_param error_auth error_data err_data error.param error_busi product.error_busi
        common.invalid_shop error_shop error_shop_not_found error_auth_shop_not_found error_param_shop_id_not_found
        error_not_exists error_item_not_found error_item_or_variation_not_found error_item_not_belong_shop
        error_invalid_item_list error_nil_shopid_or_itemid order.order_list_invalid_time error_update_time_range
        warehouse.error_can_not_find_warehouse warehouse.error_not_in_whitelist warehouse.error_region_can_not_blank
        warehouse.error_region_not_valid warehouse.error_shop_id_can_not_blank
        error_holiday_on_add_item error_holiday_mode_change_stock error_reach_shop_item_limit
        error_category_is_block error_forbidden_category error_brand_forbidden error_repeated_mtsku
      ] + %w[
        error_auth_model_is_pff error_auth_product_is_pff error_attribute_fda_error error_busi_attribute_error
        error_busi_cannot_delete_all_model error_busi_cannot_delist_reviewing_or_banned_item
        error_busi_cannot_edit_vsku error_busi_cannot_update_field error_busi_item_status_invalid
        error_busi_price_lower_then_wholesale_price error_busi_update_stock_failed
        error_cannot_update_price_in_promotion error_cannt_be_no_variation_in_promotion
        error_cannt_change_tier_variation_in_promotion error_cannt_delete_option_in_promotion
        error_cannt_edit_description_in_promotion error_cannt_edit_estimated_days_in_promotion
        error_cannt_edit_image_in_promotion error_cannt_edit_name_in_promotion
        error_cannt_edit_pre_order_in_promotion error_cannt_edit_price_in_promotion
        error_cannt_edit_stock_in_promotion error_cannt_init_tier_in_promotion error_cannt_unlisted_in_promotion
        error_category_dts error_category_level error_category_path_count_limit error_check_luc_fail
        error_cnsc_shop_block_update_tier_variation error_desc_hash_tag_over_limit error_desc_image_no_pass
        error_desc_length_min_limit error_duplicate_modelid error_duplicated_brand
        error_edit_item_price_for_item_has_model error_edit_item_stock_for_item_has_model
        error_estimated_days_limit error_flash_sale_days_to_ship_lock error_image_num_min error_image_unavailable
        error_in_item_promotion_description_lock error_in_item_promotion_image_item_lock
        error_in_item_promotion_item_price_lock error_in_item_promotion_name_item_lock
        error_in_item_promotion_nomodel_to_models error_in_item_promotion_remove_model
        error_in_item_promotion_unlsit_lock error_incalid_brand error_incalid_category error_invalid_attribute
        error_invalid_attribute_value error_invalid_brand error_invalid_category error_invalid_category_attribute
        error_invalid_days_to_ship error_invalid_language error_invalid_logistic_info error_invalid_price
        error_invalid_price_for_logistic error_item_in_promotion error_item_name_empty error_item_name_is_too_short
        error_item_uneditable error_less_required_attribute error_less_required_brand error_model_count_over_limit
        error_model_duplicate_name error_model_duplicate_tier_variation_index error_model_empty_tier_index_nonempty
        error_model_nonempty_itemtier_empty_index error_model_tier_index_bound
        error_model_tier_index_level_mismatch_var_level error_model_update_stock_model_in_promotion
        error_name_length_limit error_nil_item_in_req error_nil_name_new_item
        error_param_category_not_support_pre_order error_param_dts_exceeds_max_limit error_param_item_status
        error_param_validate error_price_exceed_max_limitt error_price_exceed_min_limitt error_price_out_of_range
        error_price_should_be_same_for_wholesales error_promotion_cantnot_update_stock
        error_query_condition_list_limit error_query_over_itemid_size error_query_query_limit_too_large
        error_related_product_in_promotion error_set_normal_unlisted_item error_slash_price_load
        error_slash_price_models_diff error_slash_price_not_lowest error_tier_img_not_allower error_tier_img_old_app
        error_tier_img_partial error_tier_index error_tier_opt_too_many error_tier_opt_val_too_long error_tier_var_is_
        error_tier_var_level_not_same error_tier_var_name_too_long error_tier_var_too_many
        error_title_character_forbidden error_title_exceeds_max_length error_unlist_in_promotion
        error_unlist_item_all_failed error_unlist_item_fail error_value_id_must_equal_zero error_value_name_required
        error_video_info_not_found error_whole_sale_min_count_incorrect error_whole_sale_price_setting_incorrect
        error_wholesale_price_less_than_ratio_limit error_wms_shop_block_upate_stock error_wrong_attrsnapshot
        error_wrong_modelid
      ] + ["error attribute", "error brand", "error category"]
    }.each_value(&:freeze).freeze

    BY_CODE = CODES.flat_map { |klass, codes| codes.map { |code| [code, klass] } }.to_h.freeze

    module_function

    # => the ApiError subclass for this pair; ApiError itself when the code is not documented.
    def classify(code, message)
      code = code.to_s
      message = message.to_s
      rule = MESSAGE_RULES.find do |rule_code, pattern, _|
        (rule_code.nil? || rule_code == code) && message.match?(pattern)
      end
      name = rule ? rule.last : BY_CODE[code]
      name ? ShopeeRbApi.const_get(name) : ApiError
    end

    # An HTTP-level failure with no Shopee error body.
    def classify_status(status)
      return RateLimitError if status == 429
      return ServerError if status >= 500

      ApiError
    end
  end
  private_constant :ErrorTable
end
