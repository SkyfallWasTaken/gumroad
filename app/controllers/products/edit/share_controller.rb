# frozen_string_literal: true

class Products::Edit::ShareController < Products::Edit::BaseController
  before_action :ensure_published

  def edit
    set_title

    render inertia: "Products/Edit/Share", props: all_tab_props.merge(active_tab: "share")
  end

  def update
    begin
      ActiveRecord::Base.transaction do
        update_share_settings
      end
    rescue ActiveRecord::RecordNotSaved, ActiveRecord::RecordInvalid, Link::LinkInvalid => e
      error_message = @product.errors.full_messages.first || e.message
      return handle_save_error(error_message, product_edit_share_path(@product.unique_permalink))
    end

    redirect_back fallback_location: product_edit_share_path(@product.unique_permalink),
                  notice: "Changes saved!"
  end

  private
    def ensure_published
      return if @product.published?

      redirect_to product_edit_product_path(@product.unique_permalink),
                  alert: "Not yet! You've got to publish your awesome product before you can share it with your audience and the world."
    end

    def update_share_settings
      @product.assign_attributes(product_permitted_params.slice(
        :taxonomy_id,
        :is_adult,
        :display_product_reviews,
        :discover_fee_per_thousand
      ))

      @product.save_tags!(product_permitted_params[:tags] || [])
      @product.show_in_sections!(product_permitted_params[:section_ids] || [])

      @product.save!
    end
end
