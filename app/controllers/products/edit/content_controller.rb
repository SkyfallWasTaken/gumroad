# frozen_string_literal: true

class Products::Edit::ContentController < Products::Edit::BaseController
  def edit
    set_title

    render inertia: "Products/Edit/Content", props: all_tab_props.merge(active_tab: "content")
  end

  def update
    begin
      ActiveRecord::Base.transaction do
        update_content
      end
    rescue ActiveRecord::RecordNotSaved, ActiveRecord::RecordInvalid, Link::LinkInvalid => e
      error_message = @product.errors.full_messages.first || e.message
      return handle_save_error(error_message, edit_link_content_path(@product.unique_permalink))
    end

    redirect_back fallback_location: edit_link_content_path(@product.unique_permalink),
                  notice: "Changes saved!"
  end

  private
    def update_content
      rich_content = product_permitted_params[:rich_content] || []
      rich_content_params = [*rich_content]

      if product_permitted_params[:variants].present?
        product_permitted_params[:variants].each { rich_content_params.push(*_1[:rich_content]) }
      end

      rich_content_params.each { |rc| rc[:description] = rc.dig(:description, :content) }

      SaveFilesService.perform(@product, product_permitted_params, rich_content_params)
      save_rich_contents(rich_content)
      update_variant_rich_contents

      finalize_content_save
    end

    def save_rich_contents(rich_content)
      rich_contents_to_keep = []
      existing_rich_contents = @product.alive_rich_contents.to_a

      rich_content.each.with_index do |product_rich_content, index|
        rc = existing_rich_contents.find { |c| c.external_id === product_rich_content[:id] } || @product.alive_rich_contents.build
        product_rich_content[:description] = SaveContentUpsellsService.new(
          seller: @product.user,
          content: product_rich_content[:description],
          old_content: rc.description || []
        ).from_rich_content

        rc.update!(
          title: product_rich_content[:title].presence,
          description: product_rich_content[:description].presence || [],
          position: index
        )
        rich_contents_to_keep << rc
      end

      (existing_rich_contents - rich_contents_to_keep).each(&:mark_deleted!)
    end

    def update_variant_rich_contents
      return unless product_permitted_params[:variants].present?

      product_permitted_params[:variants].each do |variant_params|
        variant = @product.alive_variants.find { _1.external_id == variant_params[:id] }
        next unless variant && variant_params[:rich_content].present?

        existing_rich_contents = variant.alive_rich_contents.to_a
        rich_contents_to_keep = []

        variant_params[:rich_content].each.with_index do |rc_params, index|
          rc = existing_rich_contents.find { |c| c.external_id === rc_params[:id] } || variant.alive_rich_contents.build
          rc_params[:description] = SaveContentUpsellsService.new(
            seller: @product.user,
            content: rc_params[:description],
            old_content: rc.description || []
          ).from_rich_content

          rc.update!(
            title: rc_params[:title].presence,
            description: rc_params[:description].presence || [],
            position: index
          )
          rich_contents_to_keep << rc
        end

        (existing_rich_contents - rich_contents_to_keep).each(&:mark_deleted!)
      end
    end

    def finalize_content_save
      @product.is_licensed = @product.has_embedded_license_key?
      @product.is_multiseat_license = false unless @product.is_licensed

      @product.save!
      @product.generate_product_files_archives!
    end
end
